#!perl -w
use strict;

use Path::Class;
use File::Find;
use List::MoreUtils qw(zip);
use Decision::Depends;
use File::Temp qw( tempfile );
use App::ImageStream::Config::Items;
use Config::Cascade;
use App::ImageStream::List;
use App::ImageStream::Image;
use DateTime;
use DateTime::Duration;
use Hash::Merge;
use Data::Dumper;
use Archive::Tar;
use Archive::Dir;

use vars qw($VERSION);
$VERSION = '0.03';

BEGIN {
    ${^WIN32_SLOPPY_STAT} = 1;
}

use vars qw'%thumbnail_handlers';

my $cfg = Config::Cascade->collect(
    \%App::ImageStream::Config::Items::items,
    
    config_default => 'imagestream.cfg',
    # config_file => 'imagestream.cfg',
    env => 'IMAGESTREAM_',

    getopt => {
        'f|force' => \my $force,
    },
);

my $inkscape = $cfg->{inkscape}->[0];

Decision::Depends::Configure({ Force => $force });

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
        my $thumbname = file( $output_directory, $info->thumbnail_name( $s ));
        warn "$info->{file} generates empty thumb"
            if $thumbname eq "";
        
        if (test_dep( -target => "$thumbname", -depend => $info->{file}->stringify )) {
            # XXX The svg/bitmap handler dispatch should go here
            #warn "Creating thumbnail  $thumbname " . ($info->{blob} ? "from blob" : "");
            $cache = $info->create_thumbnail($thumbname,$rotate,$s,$cache);
        } else {
            $info->set_thumbnail_info($thumbname,$s);
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
    system($cmd) == 0
        or warn "Couldn't run [$cmd]: $!/$?";
    
    # create the thumbnail(s)
    my $blob = $info->{file}->slurp(iomode => '<:raw');
    $info->{blob} = \$blob;
    $info->{blob_type} = 'png';
    unlink $tempfile
        or status 1, "Couldn't remove temporary file '$tempfile'";

    create_thumbnail_sizes($info,$output_directory,0,$sizes);    
};

sub create_thumbnail {
    # XXX Should we use only squares and cut?
    # Or is this just a problem of the CSS / Slideshow / Templates?
    my ($info,$output_directory,$sizes) = @_;
    $sizes ||= [160]; # XXX Do we still want this? App::ImageStream::Config::Defaults has these
    
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
        create_thumbnail($info,$output_directory,$sizes);
        $info->release_metadata;
    };
}

my @images = collect_images($cfg->{collect},$cfg->{reject} );
my %found = map { $_ => $_ } @images;

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

# To sort the images by timestamp of last modification (descending),
# we need to fetch the statistics for all files...
@images = sort { $b->{mtime} <=> $a->{mtime} }
          map { App::ImageStream::Image->new( file => $_ ) } values %found;

my @selected;

# To reduce IO, we only read the metadata of images that pass the
# other criteria. This prevents us from using grep ...
status 1, sprintf "Filtering %d images", scalar @images;
# XXX Make status message out of this warning

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

@images = (); # discard the remaining images, if any, to free up some more memory

status 1, sprintf "Found %d images", scalar @selected;
my $theme = $cfg->{theme}->[0];
if (-d "templates/$theme") {
    $theme = Archive::Dir->new("templates/$theme")
} elsif ($theme =~ /(?:\.tar(\.gz)?|\.tgz)$/i) {
    $theme = Archive::Tar->new("templates/$theme")
} else {
    die "Can't find theme '$theme'";
};

my %seen;
for my $format (qw(atom rss html)) {
    my $template;
    if ($theme->contains_file("imagestream.$format")) {
        $template = $theme->get_content("imagestream.$format");
    };
    $seen{ "imagestream.$format" }++;
    App::ImageStream::List->create(
        $format => file( @{ $cfg->{ output } }, "imagestream.$format" ),
        $template,
        $cfg,
        @selected
    );
}

# copy all other files from the theme
for my $file ($theme->list_files) {
    next
        if $seen{ $file };
    my $target = file(@{ $cfg->{ output } }, $file );
    status 1, "Copying $file";
    $theme->extract_file($file, $target);
};

status 2, sprintf "Done (%d seconds)", time() - $^T;

# XXX upload /rsync the complete output directory