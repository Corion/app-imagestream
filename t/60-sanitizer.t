#!perl -w
use strict;
use Test::More;
use Data::Dumper;

use App::ImageStream::Image;
use utf8;
binmode DATA, ':utf8';
my @tests = map { s!\s+$!!g; [split /\|/] } grep {!/^\s*#/} <DATA>;

push @tests, ["String\nWith\n\nNewlines\r\nEmbedded","String_With_Newlines_Embedded"];
push @tests, ["","",'Empty String'];

plan tests => 1+@tests*2;

for (@tests) {
    my $name= $_->[2] || $_->[1];
    is App::ImageStream::Image::sanitize_name($_->[0]), $_->[1], $name;
    is App::ImageStream::Image::sanitize_name($_->[1]), $_->[1], "'$name' is idempotent";
};

is_deeply [App::ImageStream::Image::sanitize_name(
    'Lenny', 'Motörhead'
)], ['Lenny','Motorhead'], "Multiple arguments also work";__DATA__
Grégory|Gregory
   Leading Spaces|Leading_Spaces
   Trailing Space|Trailing_Space
Ævar Arnfjörð Bjarmason|AEvar_Arnfjord_Bjarmason
forward/slash|forward_slash
Ümloud feat. ß|Umloud_feat._ss