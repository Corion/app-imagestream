#!perl -w
use strict;
use Test::More tests => 1;
use Data::Dumper;

use Config::Spec::FromPod 'parse_pod_config';

my $got = +{ parse_pod_config(<<'=cut') };

=head1 CONFIGURATION

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

=cut

my $expected = {
    'collect' => {
                   'spec' => 'DIR',
                   'desc' => 'Lists a single directory, from which all files will get collected.
Files in subdirectories will also be collected.
Example:
  collect \'C:/Photos\';',
                   'name' => 'collect',
                   'repeat' => undef,
                   'default' => undef,
                   'arg_count' => 1,
                  'label' => 'Collect images from',
                 },
    'reject' => {
                  'spec' => 'REGEX',
                  'desc' => 'A single expression or substring for files or directories that will
not get collected.
This is convenient for excluding backup directories etc.
Example:
  reject \'Copy of \';',
                  'name' => 'reject',
                  'repeat' => undef,
                  'default' => undef,
                  'arg_count' => 1,
                  'label' => 'Rejection list',
                }
};

is_deeply $got, $expected, "Simple POD works"
    or diag Dumper $got;