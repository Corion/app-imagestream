#!perl -w
use strict;
use Path::Class;
use File::Find;
use List::MoreUtils qw(zip);
use Decision::Depends;
use File::Temp qw( tempfile );
use App::ImageStream::Config::Items;
use App::ImageStream::Config::DSL;
use App::ImageStream::Config::Getopt;
use App::ImageStream::List;
use App::ImageStream::Image;
use DateTime;
use DateTime::Duration;
#use Data::Dumper;

use vars qw($VERSION);
$VERSION = '0.02';

BEGIN {
    ${^WIN32_SLOPPY_STAT} = 1;
}

use vars qw'%thumbnail_handlers $cfg';

# Make these override $cfg
#use Getopt::Long;
my ($ok,$opt_commandline) = App::ImageStream::Config::Getopt->get_options(
    \%App::ImageStream::Config::Items::items,
    'f|force' => \my $force,
    'c|config' => \my $config,
);
$config ||= 'imagestream.cfg';

$cfg = App::ImageStream::Config::DSL->parse_config_file(
    \%App::ImageStream::Config::Items::items,
    $config,
);

my $inkscape = $cfg->{inkscape}->[0] || 'C:\\Programme\\Inkscape\\inkscape.exe';

Decision::Depends::Configure({ Force => $force });

sub collect_images {
    my ($search,$reject) = @_;
    my @images;
    my $re_reject = join "|", map { qr/$_/i } @$reject;
    find( sub {
        if ($File::Find::name =~ /$re_reject/) {
            if (-d) {
                $File::Find::prune = 1;
            };
            # XXX Make rejection message/verbosity configurable
            warn "Rejecting '$File::Find::name'\n";
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
    my $i;
    for my $s (@$sizes) {
        my $thumbname = file( $output_directory, $info->thumbnail_name( $s ));
        warn "$info->{file} generates empty thumb"
            if $thumbname eq "";
        
        if (test_dep( -target => "$thumbname", -depend => $info->{file}->stringify )) {
            # XXX The svg/Imager handler dispatch should go here
            $i = $info->create_thumbnail($thumbname,$rotate,$s,$i);
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
    # XXX Class::Path doesn't support binmode on ->slurp :-(
    my $blob = do { 
                    local $/;
                    open my $fh, $tempfile
                        or warn "Couldn't read '$tempfile'";
                    binmode $fh;
                    <$fh>
                  };
    $info->{blob} = \$blob;
    $info->{blob_type} = 'png';
    unlink $tempfile
        or warn "Couldn't remove temporary file '$tempfile'\n";

    create_thumbnail_sizes($info,$output_directory,0,$sizes);    
};

sub create_thumbnail {
    # XXX Should we use only squares and cut?
    # Or is this just a problem of the CSS / Slideshow / Templates?
    my ($info,$output_directory,$sizes) = @_;
    $sizes ||= [160];
    
    if (my $handler = $thumbnail_handlers{ $info->{extension} }) {
        #warn $info->{file} . "(svg)";
        $handler->($info,$output_directory,$sizes);
    } else {
        #warn $info->{file} . "(file)";
        create_thumbnail_sizes($info,$output_directory,$info->{rotate},$sizes);
    }
}

sub create_thumbnails {
    my ($output_directory, $sizes, @files) = @_;
    
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
warn sprintf "Filtering %d images\n", scalar @images;
# XXX Make status message out of this warning

my $cutoff = time() - $cfg->{cutoff}->[0] * 24 * 3600;
my %exclude_tag = map { uc $_ => 1 } @{ $cfg->{exclude_tag} };

# XXX Make these configurable
my $dt_reference = DateTime->now;
my $last_time = DateTime->from_epoch( epoch => 1 );
my $distance = DateTime::Duration->new( hours => 5  );
my $ref_date;

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
        #warn $ref_date;
        $last_time = $capture_date->clone;
    };
    $last_time = $capture_date;
    push @{ $info->{tags} }, $ref_date;
    
    if (! grep { exists $exclude_tag{uc $_} } @{ $info->{exif}->{Keywords} }) {
        push @selected, $info;

        # Create thumbnail directly instead of keeping the image preview in memory
        # XXX Ideally, we should check whether the new file is different
        # from the old file before creating a new timestamp
        # XXX Move thumbnail creation into its own thread via Thread::Queue
        #     so we can get a bit faster
        create_thumbnails(@{ $cfg->{ output } },$cfg->{ size },$info);
        
        # Save some memory by releasing some image data as early as possible
        $info->release_metadata();
    } else {
        # XXX verbose: output rejection status
    }
}
@images = (); # discard the remaining images, if any, to free up some more memory

warn sprintf "Found %d images\n", scalar @selected;
for my $format (qw(atom rss html)) {
    App::ImageStream::List->create(
        $format => file( @{ $cfg->{ output } }, "imagestream.$format" ),
        $cfg,
        @selected
    );
}

# XXX upload /rsync the complete output directory