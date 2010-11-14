#!perl -w
use strict;
use Test::More tests => 1;
use Data::Dumper;

use Config::Spec::FromPod 'parse_pod_config';

my $got = +{ parse_pod_config(<<'=cut') };

=head1 CONFIGURATION

=head2 C<< item ARG >>
  
Label
  
Item description

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
  item => {
      name =>  'item',
      desc => 'Item description',
      label => 'Label',
      arg_count => 1,
      spec  => 'ARG',
      desc  => 'Item description',
      repeat => undef,
      default => undef,
  },
  theme => {
      name =>  'theme',
      desc => "Specifies the theme directory to use. You can use a themepack (.tar.gz)
or a directory.
Example:
  theme 'fancy.tar.gz'
May appear only once.",
      label => 'Theme',
      arg_count => 1,
      spec  => 'DIR',
      repeat => 1,
      default => 'plain',
  },
};

is_deeply $got, $expected, "Documented config data works"
    or diag Dumper $got;