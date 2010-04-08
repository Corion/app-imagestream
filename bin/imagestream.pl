#!perl -w
use strict;
use Path::Class;
use File::Find;
#use Memoize;
use List::MoreUtils qw(zip);
use Decision::Depends;
use Imager;
use Image::ExifTool qw(:Public);
use Image::Thumbnail;
use File::Temp qw( tempfile );

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

#my $dec = Decision::Depends->new();

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

sub create_thumbnail {
    # XXX Should we use only squares and cut?
    # Or is this a problem of the CSS / Slideshow / Templates?
    my ($info,$target,$sizes) = @_;
    $sizes ||= [160];
    
    # First see whether Image::ExifTool can extract a thumbnail for us
    # We should also rotate the thumbnail according to the Exif rotation!
    my $img_info = ImageInfo( $info->{file}->stringify, ['PreviewImage','KeyWords','Orientation'], { List => 1 } );

    # XXX Extension-based filetype handling isn't all that hot, but easier
    #     than pulling in File::MMagic or File::MimeMagic etc.
    (my $extension = lc $info->{file}->stringify) =~ s/.*\.//;

    my $rotate = $rotation{ $img_info->{Orientation} || '' };
    warn "Unknown image orientation '$img_info->{Orientation}'"
        unless defined $rotate;
    
    # If we can find an embedded preview image, use that:
    if ($img_info and $img_info->{PreviewImage}) {
        create_thumbnail_sizes(\$img_info->{PreviewImage},$target,$sizes);
    } elsif (my $handler = $thumbnail_handlers{ $extension }) {
        $handler->($info,$target,$sizes);
    }
}

sub create_thumbnails {
    my ($output_directory, $size, @files) = @_;
    for my $info (@files) {
        my $target = $info->{file}->basename;
        
        # XXX Better name generation wanted here, for clashing filenames
        #     in different directories
        $target =~ s/\.(\w+)$/_%03d_t.jpg/i;
        $target = file( $output_directory, $target );
        create_thumbnail($info,$target,$size);
    };
}

sub output_image_list {
}

sub read_config {
}

read_config();

my (@collect,@reject,%found,@preferred, $output_directory,$minimum,@sizes);

# Configuration DSL
sub collect($) {
    push @collect, @_;
};

sub reject($) {
    push @reject, @_;
};

sub prefer($$) {
    push @preferred, [ $_[0], $_[1] ];
};

sub output($) {
    $output_directory = shift;
};

sub minimum($) {
    $minimum = shift;
};

sub size($) {
    push @sizes, shift;
};

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

reject '\b.git\b';
reject '\bThumbs.db$';

# XXX We should recognize (image) file types

collect '//aliens/corion/backup/Photos/20100305 - Frankfurt Industrie Osthafen';
collect 'C:/Dokumente und Einstellungen/corion/Eigene Dateien/Eigene Bilder/Martin-svg';
minimum 100;

# If we have both, .CR2 and .JPG, prefer .CR2
# This should become configurable
# Maybe this "DSL" is the configuration
prefer '.cr2' => '.jpg';
prefer '.svg' => '.jpg';
prefer '.svg' => '.png';

size 160;
size 640;

output 'OUTPUT';

my @images = collect_images(\@collect,\@reject);
%found = map { $_ => $_ } @images;

# Weed out the duplicates
for (@preferred) {
    my ($better, $worse) = @$_;
    for (grep {/$better/i} (keys %found)) {
        my ($image) = $_;
        $image =~ s/$better//i;
        delete $found{ $image . lc $worse };
        delete $found{ $image . uc $worse };
    };
};

#print "$_\n" for sort keys %found;

# XXX Sort the images by timestamp of last modification (descending)
@images = sort { $b->{mtime} <=> $a->{mtime} }
          collect_image_information( values %found );

my $cutoff = time - 3 * 24 * 3600;
my @selected = grep { $_->{mtime} > $cutoff } @images;
if (@selected < $minimum) {
    @selected = grep {defined} @images[0..$minimum-1];
};

#print "$_->{file}\n" for @selected;

# XXX Generate the names for the output in output_directory

create_thumbnails($output_directory,[160,640],@selected);
output_image_list();

# XXX upload