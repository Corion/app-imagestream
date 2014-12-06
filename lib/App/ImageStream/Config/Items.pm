package App::ImageStream::Config::Items;
use strict;
use Config::Spec::FromPod qw(parse_pod_config);

=head1 NAME

App::ImageStream::Config::Items - metadata on config items

=head1 SYNOPSIS

  use App::ImageStream::Config::Items;
  use App::ImageStream::Config::Getopt;
  App::ImageStream::Config::Getopt::get_options(
      \%App::ImageStream::Config::Items::items,
      @ARGV
  ) or die "Bad command line arguments";

=cut

use vars qw(%items $config_raw);

$config_raw = <<'=cut';

=head1 CONFIGURATION

=head2 C<< output DIR >>

=for config
    repeat  => 1,

Output directory

Specifies the output directory into which the output will be written.

Example:

  output 'C:/ImageStream/';

May appear only once.


=head2 C<< theme DIR >>

Theme

Specifies the theme directory to use. You can use a themepack (.tar.gz)
or a directory.

Example:

  theme 'fancy.tar.gz'

May appear only once.

=for config
    repeat  => 1,
    default => 'plain',

=head2 C<< collect DIR >>

Collect images from

Lists a single directory, from which all files will get collected.
Files in subdirectories will also be collected.

Example:

  collect 'C:/Photos';

=head2 C<< reject REGEX >>

Rejection list

A single expression or substring for files or directories that will
not get collected.
This is convenient for excluding backup directories etc.

Example:

  reject 'Copy of ';

=head2 C<< cutoff COUNT >>

The number of days we look backwards in history to create the image stream.

Example:

  # show all files touched in the last week
  cutoff 7;

Default:

  cutoff 3;

May appear only once.

=head2 C<< minimum COUNT >>

The minimum number of files that will always be shown, even if you have not
changed enough files recently.

Example:

  # show 150 images minimum
  minimum 150;

Default:

  minimum 100;

May appear only once.

=head2 C<< exclude_tag TAG >>

Lists tag information that will be used to exclude images
from publication.

Example:

  exclude_tag 'family';

=head2 C<< size NAME, SIZE >>

Specify a size of images to be created. The size will specify
the maximum width and height.

Example:

  size 'thumbnail', 160;
  size 'medium', 1024;

Default:

  size 'thumbnail', 160;
  size 'medium', 800;
  size 'large', 1600;

=head2 C<< prefer EXT, EXT >>

If you have image files that are the by-product of other files,
like bitmap files created by exporting vector files, this allows
you to prefer the better-quality files over their otherwise identical
derivatives.

Example:

  # Prefer RAW files over JPG images
  prefer '.cr2', '.jpg';
  
  # Prefer SVG over PNG and JPG
  prefer '.svg', '.png';
  prefer '.svg', '.jpg';

=head2 C<< author NAME >>

Name of the author

This sets the author that is displayed for all images in the
Atom and RSS feeds.

Example:

  author 'A. U. Thor';

=head2 C<< base URL >>

=for config
    default => 'http://datenzoo.de/image_stream',

Base URL under which the gallery+feed can be reached

Example:

  base 'http://datenzoo.de/image_feed'

=head2 C<< title NAME >>

Title of your feed

Example:

  title 'All my pictures'

=head2 C<< inkscape PATH >>

=for config
    repeat  => 1,
    default => 'C:\\Programme\\Inkscape\\inkscape.exe',

Path to your Inkscape executable

This is used to locate the Inkscape program, which is needed to
convert SVG files to PNG bitmap files.

Example:

  inkscape 'C:/Program Files/Inkscape/inkscape.exe'

=head2 C<< jobs COUNT >>

Number of threads to use.

This is used to specify the number of parallel threads of execution
that will be launched to convert images.

Example:

  jobs 4

=head2 C<< verbose LEVEL >>

=for config
    default => 1,

Output progress level

This is the level of verbosity. 0 means no output except in error cases.
Default is 1. Maximum is 99.

Example:

  verbose 2

=cut

# Parse the config items from the documentation
%items = parse_pod_config( $config_raw );

1;