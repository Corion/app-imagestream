#!perl -w
use strict;
use Test::More tests => 1;
use Data::Dumper;

use Config::Spec::FromPod 'parse_pod_config';

my $got = +{ parse_pod_config(<<'=cut') };

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

=cut

my $expected = {
          'output' => {
                        'spec' => 'DIR',
                        'desc' => 'Specifies the output directory into which the output will be written.
Example:
  output \'C:/ImageStream/\';
May appear only once.',
                        'name' => 'output',
                        'repeat' => 1,
                        'default' => undef,
                        'label' => 'Output directory',
                        'arg_count' => 1
                      },
          'theme' => {
                       'spec' => 'DIR',
                       'desc' => "Specifies the theme directory to use. You can use a themepack (.tar.gz)
or a directory.
Example:
  theme 'fancy.tar.gz'
May appear only once.",
                       'name' => 'theme',
                       'repeat' => '1',
                       'default' => 'plain',
                       'label' => 'Theme',
                       'arg_count' => 1
                     },
};

is_deeply $got, $expected, "Out-of-band config data works"
    or diag Dumper $got;