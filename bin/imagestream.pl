#!perl -w
use strict;
use Path::Class;
use File::Find;
use List::MoreUtils qw(zip);
use Decision::Depends;
use Imager;
use Image::ExifTool qw(:Public);
use Image::Thumbnail;
use File::Temp qw( tempfile );
use App::ImageStream::Config::Items;
use App::ImageStream::Config::DSL;
use Data::Dumper;

use Getopt::Long;
GetOptions(
    'f|force' => \my $force,
    'i|inkscape' => \my $inkscape,
);

$inkscape ||= 'C:\\Programme\\Inkscape\\inkscape.exe';

Decision::Depends::Configure({ Force => $force });

sub collect_images {
    my ($search,$reject) = @_;
    my @images;
    find( sub {
        for (@$reject) {
            if ($File::Find::name =~ /$_/) {
                $File::Find::prune = 1;
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

use vars qw'%rotation %thumbnail_handlers';

%rotation = (
    ''                    => 0,
    'Horizontal (normal)' => 0,
    'Rotate 270 CW'       => 270,
);

my $dec = Decision::Depends->new();

%thumbnail_handlers = (
    'svg'  => \&extract_thumbnail_svg,
    'svgz' => \&extract_thumbnail_svg,
);

sub create_thumbnail_from_blob {
    my ($info,$thumbname,$rotate,$size,$i) = @_;
    # XXX We're Imager-specific here
    if (! $i) {
        if ($info->{blob}) {
            $i = Imager->new->read(data => ${$info->{blob}});
        } else {
            $i = Imager->new->read(file => "$info->{file}");
        };
        $i = $i->rotate(degrees => $rotate) if $rotate;
    };
    
    my $t = Image::Thumbnail->new(
        module     => 'Imager',
        object     => $i,
        size       => $size,
        quality    => 90,
        outputpath => $thumbname,
        create => 1,
    );
    
    return $i;
}

sub create_thumbnail_sizes {
    my ($info,$target,$rotate,$sizes) = @_;
    my $i;
    for my $s (@$sizes) {
        my $thumbname = sprintf($target, $s);
        
        if (test_dep( -target => $thumbname, -depend => $info->{file} )) {
            $i = create_thumbnail_from_blob($info,$thumbname,$rotate,$s,$i);
        } else {
            #warn "$thumbname is newer than $info->{file}->basename";
        }
    }
};

sub extract_thumbnail_svg {
    # create a temporary PNG image from which we'll subsequently
    my ($info,$target,$sizes,$force) = @_;
    my ($fh, $tempfile) = tempfile();
    close $fh; # we're on Windows
    my $source = $info->{file};

    my $cmd = qq{"$inkscape" -D "--export-png=$tempfile" --export-text-to-path --without-gui "$source"};
    system($cmd) == 0
        or warn "Couldn't run [$cmd]: $!/$?";
    
    # create the thumbnail(s)
    my $blob = do {
        local $/;
        open my $fh, '<', $tempfile
            or die "Couldn't read '$tempfile': $!";
        binmode $fh;
        <$fh>;
    };
    $info->{blob} = \$blob;
    create_thumbnail_sizes($info,$target,0,$sizes);
    
    unlink $tempfile
        or warn "Couldn't remove temporary file '$tempfile'\n";
};

sub fetch_image_metadata {
    my ($info,$target) = @_;

    my $img_info = ImageInfo(
        $info->{file}->stringify,
        ['PreviewImage','KeyWords','Orientation'],
        { List => 1 }
    );
    $info->{exif} = $img_info;

    # XXX Extension-based filetype handling isn't all that hot, but easier
    #     than pulling in File::MMagic or File::MimeMagic etc.
    (my $extension = lc $info->{file}->stringify) =~ s/.*\.//;
    $info->{extension} = $extension;

    my $rotate = $rotation{ $img_info->{Orientation} || '' };
    warn "Unknown image orientation '$img_info->{Orientation}'"
        unless defined $rotate;
    $info->{rotate} = $rotate;
    
    $info
}

sub generate_thumbnail_name {
    my ($info,$size, $target) = @_;
    $target =~ /(.*)\.\w+$/;
    $target = $1;
    my $extension = $info->{extension};

    my @tags = @{ $info->{exif}->{KeyWords} || []};
    my $dir = $info->{file}->dir->relative($info->{file}->dir->parent);
    push @tags, $dir;
    warn $dir;
    
    # make uri-sane filenames
    # XXX Maybe use whatever SocialText used to create titles
    # XXX If I can't find this, make this into its own module
    my $tags = join "_", @tags;
    $tags =~ s/['"]//gi;
    $tags =~ s/[.^a-zA-Z0-9-]/ /gi;
    $tags =~ s/\s+/_/g;
    
    my @parts = qw(file size tags extension);
    my %parts = (
        file => $target,
        extension => $extension,
        size => sprintf( '%04d', $size ),
        tags => $tags,
    );
    $target = join "_", @parts{ @parts };
        
    # Clean up the end result
    # This fixes foo_.extension to foo.extension
    $target =~ s/_([\W])/$1/g;

    $info->{target} = $target;
    $target
}

sub create_thumbnail {
    # XXX Should we use only squares and cut?
    # Or is this just a problem of the CSS / Slideshow / Templates?
    my ($info,$target,$sizes) = @_;
    $sizes ||= [160];
    
    # If we can find an embedded preview image, use that:
    if ($info->{exif} and $info->{exif}->{PreviewImage}) {
        create_thumbnail_sizes(\($info->{exif}->{PreviewImage}),$target,$sizes);
    } elsif (my $handler = $thumbnail_handlers{ $info->{extension} }) {
        $handler->($info,$target,$sizes);
    }
}

sub create_thumbnails {
    my ($output_directory, $size, @files) = @_;
    for my $info (@files) {
        my $target = $info->{file}->basename;
        
        $target = generate_thumbnail_name($info,$size,$target);
        $target = file( $output_directory, $target );
        create_thumbnail($info,$target,$size);
    };
}

my $cfg = App::ImageStream::Config::DSL->parse_config_file(
    \%App::ImageStream::Config::Items::items,
    'imagestream.cfg'
);

warn Dumper $cfg;

#my (@collect,
#    %exclude_tags,
#    @reject,
#    %found,
#    @preferred,
#    $output_directory,
#    $minimum,
#    @sizes
#);

sub collect_image_information {
    my @res;
    my @stat_header = (qw(dev ino mode nlink uid gid rdev size atime mtime ctime blksize blocks));
    for my $img (@_) {
        my @stat = stat $img;
        my %info = zip @stat_header, @stat;
        if ($info{ size }) {
            $info{ file } = $img;
            push @res, \%info
        };
    };
    @res
}

=for later

# XXX The DSL should be a bit more formally specified by listing
#     its keywords and the parameters it takes, and the handlers,
#     instead of being eval()
#     This will help once a GUI is generated instead of just being
#     a command line app.
# Maybe Parse::Yapp or Regexp::Grammar are suitable tools to 
# specify/parse that config, or maybe we just want to use Config::GitLike
# Even if a config file is just a do{} block, we might want to create
# these subroutines only locally, as not to pollute the rest of the
# program with the keywords.

reject '\b.git\b';
reject '\bThumbs.db$';

# XXX We should recognize (image) file types

collect '//aliens/corion/backup/Photos/20100305 - Frankfurt Industrie Osthafen';
collect 'C:/Dokumente und Einstellungen/corion/Eigene Dateien/Eigene Bilder/Martin-svg';
collect 'C:/Dokumente und Einstellungen/Corion/Eigene Dateien/Eigene Bilder/20090826 - Kreuzfahrt Geiranger';
collect 'C:/Dokumente und Einstellungen/Corion/Eigene Dateien/Eigene Bilder/Circus-Circus';

minimum 100;

cutoff 3; # days

exclude_tag 'private';

# If we have both, .CR2 and .JPG, prefer .CR2
prefer '.cr2' => '.jpg';
prefer '.svg' => '.jpg';
prefer '.svg' => '.png';

# XXX Would we ever want to have more than two sizes, small and large?
size 160;
size 640;

output 'OUTPUT';

# We also need to declare the external URLs:
# base_url 'http://datenzoo.de/imagestream';
# base_file 'images'
# generate 'html','atom','rss'; # the default
# Should generate http://datenzoo.de/imagestream/images.html ,
# images.atom and images.rss

# theme 'mysite.tar.gz'
# theme 'mysite.new'
# will look for $(dirname config-file)/mysite.new/
#               $()/mysite.new.tar 
#               $()/mysite.new.tar.gz
#               $rcdir/mysite.new
#               /etc/imagestream/mysite.new
# theme '~/my.override'

=cut

my @images = collect_images($cfg->{collect},$cfg->{reject} );
my %found = map { $_ => $_ } @images;

# Weed out the duplicates
for (@{ $cfg->{preferred}}) {
    my ($better, $worse) = @$_;
    for (grep {/$better/i} (keys %found)) {
        my ($image) = $_;
        $image =~ s/$better//i;
        delete $found{ $image . lc $worse };
        delete $found{ $image . uc $worse };
    };
};

# To sort the images by timestamp of last modification (descending),
# we need to fetch the statistics for all files...
@images = sort { $b->{mtime} <=> $a->{mtime} }
          collect_image_information( values %found );

my @selected;

# To reduce IO, we only read the metadata of images that pass the
# other criteria. This prevents us from using grep ...
while (@images
         and ($images[0]->{mtime} < $cfg->{cutoff} or $cfg->{minimum} < @selected)) {
    my $info = fetch_image_metadata( shift @images );
    
    if (! grep { exists $cfg->{ exclude_tag }->{uc $_} } @{ $info->{exif}->{KeyWords} }) {
        push @selected, $info;
    } else {
        # XXX verbose: output rejection status
    }
}

create_thumbnails($cfg->{ output },$cfg->{ size },@selected);

# XXX Ideally, we should check whether the new file is different
# from the old file before creating a new timestamp
#create_rss($output_directory, @selected);
#create_atom($output_directory, @selected);
#create_html($output_directory, @selected);

# XXX upload the complete output directory