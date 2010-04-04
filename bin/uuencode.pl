#!perl -w
use strict;

my ($in) = @ARGV;
open my $fh, '<', $in
    or die "Couldn't read '$in': $!";
binmode $fh;

local $/;
print pack('u', <$fh>);
    