#!perl -w
use strict;
use Path::Class;
use File::Find;
#use Memoize;
use List::MoreUtils qw(zip);
use Imager;
use Image::ExifTool qw(:Public);
use Image::Thumbnail;

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

use vars '%rotation';

%rotation = (
    ''                    => 0,
    'Horizontal (normal)' => 0,
    'Rotate 270 CW'       => 270,
);

sub create_thumbnail {
    # XXX Should we use only squares and cut?
    # Or is this a problem of the CSS / Slideshow / Templates?
    my ($info,$target,$sizes) = @_;
    $sizes ||= [160];
    
    # First see whether Image::ExifTool can extract a thumbnail for us
    # We should also rotate the thumbnail according to the Exif rotation!
    my $img_info = ImageInfo( $info->{file}->stringify, ['PreviewImage','KeyWords','Orientation'], { List => 1 } );

    my $rotate = $rotation{ $img_info->{Orientation} || '' };
    warn "Unknown image orientation '$img_info->{Orientation}'"
        unless defined $rotate;
    
    if ($img_info and $img_info->{PreviewImage}) {
        # XXX We're Imager-specific here
        my $i = Imager->new->read( data => ${ $img_info->{PreviewImage} });
        $i = $i->rotate(degrees => $rotate) if $rotate;
        for my $s (@$sizes) {
            my $thumbname = sprintf( $target, $s);
            if (-f $thumbname) {
                my $m = (stat $thumbname)[9];
                if ($m >= $info->{mtime}) {
                    # exists and is newer than original image, so skip
                    # generation
                    next
                }
            }
            
            my $t = Image::Thumbnail->new(
                module     => 'Imager',
                object     => $i,
                size       => $s,
                quality    => 90,
                outputpath => $thumbname,
                create => 1,
            );
        }
    }
}

sub create_thumbnails {
    my ($output_directory, $size, @files) = @_;
    for my $info (@files) {
        my $target = $info->{file}->basename;
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

my (@collect,@reject,%found,@preferred, $output_directory,$minimum);

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