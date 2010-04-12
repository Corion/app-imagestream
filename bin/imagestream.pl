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
    'c|config' => \my $config,
    'i|inkscape' => \my $inkscape,
);

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

use vars qw'%rotation %thumbnail_handlers';

%rotation = (
    ''                    => 0,
    'Horizontal (normal)' => 0,
    'Rotate 270 CW'       => 270,
);

%thumbnail_handlers = (
    'svg'  => \&extract_thumbnail_svg,
    'svgz' => \&extract_thumbnail_svg,
);

sub create_thumbnail_from_blob {
    my ($info,$thumbname,$rotate,$size,$i) = @_;
    # XXX We're Imager-specific here
    if (! $i) {
        $i = Imager->new;
        if ($info->{blob}) {
            $i = $i->read(data => ${$info->{blob}}, type => $info->{blob_type}, )
                or warn sprintf "%s: %s", $info->{file}, $i->errstr;
        } else {
            $i = $i->read(file => "$info->{file}")
                or warn sprintf "%s: %s", $info->{file}, $i->errstr;
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
        size       => $size,
        quality    => 90,
        outputpath => $thumbname,
        create => 1,
    );
    
    return $i;
}

sub create_thumbnail_sizes {
    my ($info,$output_directory,$rotate,$sizes) = @_;
    my $i;
    for my $s (@$sizes) {
        my $thumbname = file( $output_directory, generate_thumbnail_name( $info, $s ));
        
        if (test_dep( -target => "$thumbname", -depend => "$info->{file}" )) {
            $i = create_thumbnail_from_blob($info,$thumbname,$rotate,$s,$i);
        } else {
            #warn "$thumbname is newer than $info->{file}->basename";
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

sub fetch_image_metadata {
    my ($info) = @_;

    # XXX We should be lighter here and only read the PreviewImage
    #     if we need it to recreate the thumbnail
    my $img_info = ImageInfo(
        $info->{file}->stringify,
        ['PreviewImage','KeyWords','Orientation'],
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

    my $rotate = $rotation{ $img_info->{Orientation} || '' };
    warn "$info->{file}: Unknown image orientation '$img_info->{Orientation}'"
        unless defined $rotate;
    $info->{rotate} = $rotate;
    
    $info
}

sub generate_thumbnail_name {
    my ($info,$size) = @_;
    (my $target = $info->{file}->basename) =~ /(.*)\.\w+$/;
    $target = $1;
    my $extension = $info->{blob_type} || $info->{extension};

    my @tags = @{ $info->{exif}->{KeyWords} || []};
    my $dir = $info->{file}->dir->relative($info->{file}->dir->parent);
    push @tags, "$dir";
    
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
    $target = join( "_", @parts{ @parts }) . "." . $extension;

    # Clean up the end result
    # This fixes foo_.extension to foo.extension

    $target =~ s/_+/_/g;
    $target =~ s/_+([\W])/$1/g;

    $target
}

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
        #my $target = $info->{file}->basename;
        create_thumbnail($info,$output_directory,$sizes);
    };
}

my $cfg = App::ImageStream::Config::DSL->parse_config_file(
    \%App::ImageStream::Config::Items::items,
    $config,
);

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
          collect_image_information( values %found );

my @selected;

# To reduce IO, we only read the metadata of images that pass the
# other criteria. This prevents us from using grep ...
while (@images
         and ($images[0]->{mtime} > $cfg->{cutoff} or $cfg->{minimum} < @selected)) {
    my $info = fetch_image_metadata( shift @images );
    
    if (! grep { exists $cfg->{ exclude_tag }->{uc $_} } @{ $info->{exif}->{KeyWords} }) {
        push @selected, $info;
    } else {
        # XXX verbose: output rejection status
    }
}

#warn $_->{file} for @selected;
create_thumbnails(@{ $cfg->{ output } },$cfg->{ size },@selected);

# XXX Ideally, we should check whether the new file is different
# from the old file before creating a new timestamp
#create_rss($output_directory, @selected);
#create_atom($output_directory, @selected);
#create_html($output_directory, @selected);

# XXX upload the complete output directory