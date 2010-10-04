package App::ImageStream::Image;
use strict;

use Imager;
use Image::ExifTool qw(:Public);
use Image::Thumbnail;
use Image::Info qw(image_info dim);
use POSIX qw(strftime);
use DateTime;

use vars qw'%rotation';

BEGIN {
    %rotation = (
        ''                    => 0,
        'Horizontal (normal)' => 0,
        'Rotate 90 CW'        => 90,
        'Rotate 270 CW'       => 270,
    );
};

=head1 METHODS

=head2 C<< ->new >>

Creates a new instance

=cut

sub new {
    my ($class,%args) = @_;
    my $self = bless \%args, $class;
    $self->stat;
    $self
};

sub create_thumbnail {
    my ($self,$thumbname,$rotate,$size,$i) = @_;
    # XXX We're Imager-specific here
    if (! $i) {
        $i = Imager->new;
        if ($self->{blob}) {
            $i = $i->read(data => ${$self->{blob}}, type => $self->{blob_type}, )
                or warn sprintf "%s: %s", $self->{file}, $i->errstr;
        } else {
            my $t = $i->read(file => $self->{file}->stringify)
                or warn sprintf "%s: %s", $self->{file}, $i->errstr;
            if (! $t) {
                return
            }
            $i = $t;
        };
        if ($i) {
            $i = $i->rotate(degrees => $rotate) if $rotate;
        } else {
            return
        }
    };
    
    my $t = Image::Thumbnail->new(
        module     => 'Imager',
        object     => $i,
        #input      => $self->{blob} || "$self->{file}",
        size       => $size,
        quality    => 95,
        outputpath => $thumbname,
        create => 1,
    );
    
    $self->set_thumbnail_info( $thumbname, $size, $t->{x}, $t->{y} );
    
    return $i;
}

sub set_thumbnail_info {
    my ($self,$thumbname,$size,$width,$height) = @_;
    $self->{sizes} ||= {};
    
    if (! exists $self->{sizes}->{$size}) {
        if (! $width) {
            my $img = image_info("$thumbname");
            ($width,$height) = dim($img);
        };
        $self->{sizes}->{$size} = {
            width  => $width,
            height => $height,
            name   => $thumbname,
        };
    };    
};

sub capture_date {
    my ($self) = @_;
    if (! $self->{ date_taken }) {
        $self->fetch_metadata();
    };
    
    my $ts = $self->{date_taken};
    if (my @t = ($ts =~ /^(\d+):(\d+):(\d+) (\d+):(\d+):(\d{2})/)) {
        my %opts;
        @opts{qw(year month day hour minute second)} = @t;
        return DateTime->new(%opts);
    } elsif (@t = ($ts =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d{2})Z/)) {
        my %opts;
        @opts{qw(year month day hour minute second)} = @t;
        return DateTime->new(%opts);
    } else {
        die "Malformed timestamp '$ts'";
    }
}

sub fetch_metadata {
    my ($info) = @_;

    # XXX We should be lighter here and only read the PreviewImage
    #     if we need it to recreate the thumbnail
    my $img_info = ImageInfo(
        $info->{file}->stringify,
        ['PreviewImage','KeyWords','Orientation','DateTimeOriginal'],
        { List => 1 }
    );
    $info->{exif} = $img_info;
    
    if ($info->{exif} and $info->{exif}->{PreviewImage}) {
        $info->{blob_type} = 'jpeg';
        $info->{blob} = $info->{exif}->{PreviewImage};
    };
    
    # XXX Extension-based filetype handling isn't all that hot, but easier
    #     than pulling in File::MMagic or File::MimeMagic etc.
    (my $extension = lc $info->{file}->stringify) =~ s/.*\.//;
    $info->{extension} = $extension;
    $info->{mime_type} = $extension eq 'png' ? 'image/png'
                       : $extension eq 'svg' ? 'image/png'
                                             : 'image/jpeg';

    $info->{date_taken} = $img_info->{DateTimeOriginal}
                          || strftime '%Y-%m-%dT%H:%M:%SZ',
                                gmtime( $info->{mtime} );

    my $rotate = $rotation{ $img_info->{Orientation} || '' };
    warn "$info->{file}: Unknown image orientation '$img_info->{Orientation}'"
        unless defined $rotate;
    $info->{rotate} = $rotate;
    
    $info
}

sub release_metadata {
    my ($self) = @_;
    undef $self->{blob};
    undef $self->{exif}->{PreviewImage};
};

sub stat {
    my ($self) = @_;
    my @stat_header = (qw(dev ino mode nlink uid gid rdev size atime mtime ctime blksize blocks));
    my @stat = stat $self->{file};
    @{ $self }{ @stat_header } = @stat;
    if (! $self->{ size }) {
        # The file got removed meanwhile or is unreadable
        return
    };
    $self
}

sub thumbnail_name {
    my ($self,$size) = @_;
    (my $target = $self->{file}->basename) =~ /(.*)\.\w+$/;
    $target = $1;
    my $extension = $self->{blob_type} || $self->{extension};

    my @tags = @{ $self->{exif}->{Keywords} || []};
    my $dir = $self->{file}->dir->relative($self->{file}->dir->parent);
    push @tags, "$dir";
    
    # Now, merge our newfound tags with the other tags we already (might) have
    $self->{tags} ||= [];    
    my %seen;
    @seen{ @{ $self->{tags} } } = (1) x @{ $self->{ tags } };
    for (@tags) {
        push @{ $self->{ tags } }, $_
            unless $seen{ $_ }++;
    }
            
    # make uri-sane filenames
    # XXX Maybe use whatever SocialText used to create titles
    # XXX If I can't find this, make this into its own module
    my $tags = join "_", @tags;
    $tags =~ s/['"]//gi;
    $tags =~ s/[^a-zA-Z0-9.-]/ /gi;
    $tags =~ s/\s+/_/g;
    $tags =~ s/_-_/-/g;
    
    my @parts = qw(file size tags);
    my %parts = (
        file => $target,
        size => sprintf( '%04d', $size ),
        tags => $tags,
    );
    $target = lc( join( "_", @parts{ @parts }) . "." . $extension );

    # Clean up the end result
    # This fixes foo_.extension to foo.extension

    $target =~ s/_+/_/g;
    $target =~ s/_+([\W])/$1/g;

    $target
}

sub title {
    my ($self) = @_;
    $self->{title} || $self->{file}->basename;
};

sub author {
    my ($self) = @_;
    $self->{author}
};


1;