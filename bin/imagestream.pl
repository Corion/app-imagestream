#!perl -w
use strict;
use Path::Class;
use File::Find;
use List::MoreUtils qw(zip);
use Decision::Depends;
use File::Temp qw( tempfile );
use App::ImageStream::Config::Items;
use App::ImageStream::Config::DSL;
use App::ImageStream::List;
use App::ImageStream::Image;
#use Data::Dumper;

BEGIN {
    ${^WIN32_SLOPPY_STAT} = 1;
}

use vars qw'%thumbnail_handlers $cfg';

# Make these override $cfg
use Getopt::Long;
GetOptions(
    'f|force' => \my $force,
    'c|config' => \my $config,
    'i|inkscape' => \my $inkscape,
);

# XXX Make these readable from the config in addition
$inkscape ||= 'C:\\Programme\\Inkscape\\inkscape.exe';
$config ||= 'imagestream.cfg';

Decision::Depends::Configure({ Force => $force });

sub collect_images {
    my ($search,$reject) = @_;
    my @images;
    find( sub {
        for (@$reject) {
            if ($File::Find::name =~ /$_/) {
                $File::Find::prune = 1;
                #warn "Rejecting '$File::Find::name' ($_)";
                last;
            }
        }
        if (! $File::Find::prune) {
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
        
        if (test_dep( -target => "$thumbname", -depend => "$info->{file}" )) {
            $i = $info->create_thumbnail($thumbname,$rotate,$s,$i);
        } else {
            #warn sprintf "%s is newer than %s" ,
            #    $thumbname,
            #    $info->{file}->basename;
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
        delete $info->{blob};
    };
}

$cfg = App::ImageStream::Config::DSL->parse_config_file(
    \%App::ImageStream::Config::Items::items,
    $config,
);

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
my $cutoff = time() - $cfg->{cutoff}->[0] * 24 * 3600;
my %exclude_tag = map { uc $_ => 1 } @{ $cfg->{exclude_tag} };
while (@images
         and ($images[0]->{mtime} > $cutoff or $cfg->{minimum}->[0] > @selected)) {
    my $info = shift @images;
    $info->fetch_metadata();
    
    if (! grep { exists $exclude_tag{uc $_} } @{ $info->{exif}->{KeyWords} }) {
        push @selected, $info;

        # Create thumbnail directly instead of keeping the image preview in memory
        create_thumbnails(@{ $cfg->{ output } },$cfg->{ size },$info);
    } else {
        # XXX verbose: output rejection status
    }
}

# XXX Ideally, we should check whether the new file is different
# from the old file before creating a new timestamp
App::ImageStream::List::create(atom => file( @{ $cfg->{ output } }, 'imagestream.atom'), $cfg, @selected);
App::ImageStream::List::create(rss  => file( @{ $cfg->{ output } }, 'imagestream.rss'), $cfg, @selected);
#create_atom($output_directory, @selected);
#create_html($output_directory, @selected);

# XXX upload the complete output directory