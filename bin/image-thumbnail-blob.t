#!perl -w
use strict;
use Test::More tests => 9;
use Image::Thumbnail;

use vars qw[$module];

my $blob = unpack 'u', do { local $/; <DATA> };
my $thumbname = "${0}_thumb.jpg";

# To extract the uuencoded image attached below:
#open my $fh, '>', "${0}_reference.jpg";
#binmode $fh;
#print $fh $blob;
#close $fh;

END {
    if (-f $thumbname) {
        unlink $thumbname
            or warn "Couldn't remove '$thumbname': $!";
    };
};

for my $module (qw[ Imager Image::Magic GD ]) {
    SKIP: {
        if (! eval "require $module; 1") {
            skip "$module not loaded ($@)", 3;
        };

        ok eval {
                Image::Thumbnail->new(
                    module     => $module,
                    input      => \$blob,
                    size       => 96,
                    quality    => 90,
                    outputpath => $thumbname,
                    create => 1,
                );
                1
        }, "Using $module, we can create a thumbnail from an in-memory blob"
            or diag $@;
            
        ok -f $thumbname, "We created a thumbnail file";
        ok -s $thumbname, "... of positive file size";
    };
};

__DATA__
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
45?;@X'`![5ESG).>>:T5^Y+/_]D`
