#!perl -w
use strict;

use Path::Class;
use File::Find;
use List::MoreUtils qw(zip);
use Decision::Depends;
use File::Temp qw( tempfile );
use App::ImageStream::Config::Items;
use Config::Collect;
use App::ImageStream;
use App::ImageStream::List;
use App::ImageStream::Image;
use DateTime;
use DateTime::Duration;
use Data::Dumper;
use DB_File; # for the cache...

use vars qw($VERSION);
$VERSION = '0.03';

BEGIN {
    ${^WIN32_SLOPPY_STAT} = 1;
}

use vars qw'%thumbnail_handlers';

sub collect_config {
    my(@files) = @_;
    my $cfg = Config::Collect->collect(
        \%App::ImageStream::Config::Items::items,
        
        config_default => 'imagestream.cfg',
        config_file => \@files,
        env => 'IMAGESTREAM_',

        getopt => {
            'f|force' => \my $force,
            # how can we override things from the config file here?!
            # Simply add @ARGV?!
        },
    );
    $cfg
};

# We should take @ARGV in consideration here...
# so that people can specify a configuration to use on the command line
my $cfg = collect_config();

# A simple sanity check so we bail out early if a theme isn't found
my $theme = App::ImageStream->get_theme($cfg);

# Merge the theme configuration here too
# This is done in a somewhat ugly way by adding the template
# configuration file(s)
# and then re-reading the whole configuration
# The template configuration files should also be a cascade
# except that our template merger facility only returns the last
# configuration file instead of returning all of them
if( $theme->contains_file('theme.cfg') ) {
    my $theme_config = $theme->get_content('theme.cfg');
    $cfg = collect_config( \$theme_config );
};

my $inkscape = $cfg->{inkscape}->[0];

sub status ($$) {
    my ($level,$message) = @_;
    if ($level <= $cfg->{verbose}->[0]) {
        print "$message\n";
    };
};

sub collect_images {
    my ($search,$reject) = @_;
    my @images;
    my $re_reject = join "|", map { qr/$_/i } @$reject;
    find( sub {
        if ($File::Find::name =~ /$re_reject/) {
            if (-d) {
                $File::Find::prune = 1;
            };
            status 3, "Rejecting '$File::Find::name'";
        } else {
            push @images, file($File::Find::name)
                if (-f $File::Find::name);
        };
    }, @$search );
    @images
}

%thumbnail_handlers = (
    'svg'  => \&extract_thumbnail_svg,
    'svgz' => \&extract_thumbnail_svg,
);

sub create_thumbnail_sizes {
    my ($info,$output_directory,$rotate,$sizes) = @_;
    my $cache;
    for my $s (reverse sort @$sizes) { # create largest thumbnail first
        my( $size_name, $size )= @$s;
        my $thumbname = file( $output_directory, $info->thumbnail_name( $size ));
        warn "$info->{file} generates empty thumb"
            if $thumbname eq "";
        
        if (test_dep( -target => "$thumbname", -depend => $info->{file}->stringify )) {
            # XXX The svg/bitmap handler dispatch should go here
            #warn "Creating '$size_name' thumbnail $thumbname " . ($info->{blob} ? "from blob" : "");
            $cache = $info->create_thumbnail($thumbname,$rotate,$size, $size_name,$cache);
        } else {
            $info->set_thumbnail_info($thumbname,$size,$size_name);
        }
    }
};

# XXX We shouldn't need to render the SVG just to potentially create thumbnails
sub extract_thumbnail_svg {
    # create a temporary PNG image from which we'll subsequently
    my ($info,$output_directory,$sizes,$force) = @_;
    my ($fh, $tempfile) = tempfile();
    close $fh; # we're on Windows
    my $source = $info->{file};
    
    my $cmd = qq{"$inkscape" -D "--export-png=$tempfile" --export-text-to-path --without-gui "$source"};
    status 7, "Running [$cmd]";
    system($cmd) == 0
        or status 0, "Couldn't run [$cmd]: $!/$?";
    
    # create the thumbnail(s)
    #my $blob = $info->{file}->slurp(iomode => '<:raw');
    my $blob = file($tempfile)->slurp(iomode => '<:raw');
    $info->{blob} = \$blob;
    $info->{blob_type} = 'png';
    unlink $tempfile
        or status 1, "Couldn't remove temporary file '$tempfile'";

    create_thumbnail_sizes($info,$output_directory,0,$sizes);
};

sub create_thumbnail {
    # XXX Should we use only squares and cut?
    # XXX Consider using the "reddit interesting image section" algorithm for squares
    # Or is this just a problem of the CSS / Slideshow / Templates?
    my ($info,$output_directory,$sizes) = @_;
    
    if (my $handler = $thumbnail_handlers{ $info->{extension} }) {
        $handler->($info,$output_directory,$sizes);
    } else {
        create_thumbnail_sizes($info,$output_directory,$info->{rotate},$sizes);
    }
}

sub create_thumbnails {
    my ($output_directory, $sizes, @files) = @_;
    
    my $start = time;
    for my $info (@files) {
        status 6, "Creating thumbnails for $info->{file}";
        
        create_thumbnail($info,$output_directory,$sizes);
        $info->release_metadata;
    };
}

my @images;
tie my %found, 'DB_File', "imagestream.cache";

if( $cfg->{from_cache}->[0] ) {
    # bam!
} else {
    @images = collect_images($cfg->{collect},$cfg->{reject} );
    %found = map { $_ => $_ } @images;
    # Weed out the duplicates
    for (@{ $cfg->{prefer}}) {
        my ($better, $worse) = @$_;
        for (grep {/$better/i} (keys %found)) {
            my ($image) = $_;
            $image =~ s/$better//i;
            my $removed = delete $found{ $image . lc $worse };
            $removed = delete $found{ $image . uc $worse };
        };
    };
};

# To sort the images by timestamp of last modification (descending),
# we need to fetch the statistics for all files...
@images = sort { $b->{mtime} <=> $a->{mtime} }
          map { App::ImageStream::Image->new( file => file($_) ) } values %found;

my @selected;

# To reduce IO, we only read the metadata of images that pass the
# other criteria. This prevents us from using grep ...
status 1, sprintf "Filtering %d images", scalar @images;

my $cutoff = time() - $cfg->{cutoff}->[0] * 24 * 3600;
my %exclude_tag = map { uc $_ => 1 } @{ $cfg->{exclude_tag} };

# XXX Make these configurable
my $dt_reference = DateTime->now;
my $last_time = DateTime->from_epoch( epoch => 1 );
my $distance = DateTime::Duration->new( hours => 5  );
my $ref_date;

my $start = time;
while (@images
         and ($images[0]->{mtime} > $cutoff or $cfg->{minimum}->[0] > @selected)) {
    my $info = shift @images;
    status 5, "Fetching metadata for " . $info->{file};
    $info->fetch_metadata();
    
    # Now, add a "date" tag to all images, grouping together those taken
    # in close succession, so wrapping over midnight doesn't break up those
    my $last_time = DateTime->from_epoch( epoch => 1 );
    my $target_directory;
    my $capture_date = $info->capture_date;
    my $this_distance = ($capture_date - $last_time);
    if ($dt_reference+$this_distance > $dt_reference+$distance) {
        $ref_date = $capture_date->strftime('%Y-%m-%d');
        $last_time = $capture_date->clone;
    };
    $last_time = $capture_date;
    push @{ $info->{tags} }, $ref_date;
    
    if (! grep { exists $exclude_tag{uc $_} } @{ $info->{exif}->{Keywords} }) {
        push @selected, $info;

        # Create thumbnail directly instead of keeping the image preview in memory
        # XXX Ideally, we should check whether the new file is different
        # from the old file before creating a new timestamp
        create_thumbnails(@{ $cfg->{ output } },$cfg->{ size },$info);
        
        # Save some memory
        $info->release_metadata();
    } else {
        status 3, "Rejected $info->{file} (tagged)";
        # XXX verbose: output rejection status
    }
}
my $taken = (time - $start) || 1;
my $rate = 0+@selected / $taken;
status 2, sprintf "Created %d thumbnails in %d seconds (%d/s)", 0+@selected, $taken, $rate;

# Update %found to only store as many files as we really need in the cache:
%found = map { $_->{file} => $_->{file} } @selected;

@images = (); # discard the remaining images, if any, to free up some more memory

status 1, sprintf "Found %d images", scalar @selected;
App::ImageStream->apply_theme(
    $cfg,
    $theme,
    $cfg->{output}->[0],
    @selected,
);

status 2, sprintf "Done (%d seconds)", time() - $^T;

# XXX upload /rsync the complete output directory