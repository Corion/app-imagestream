package App::ImageStream::List::HTML;
use strict;
use Template;

use vars qw($VERSION);
$VERSION = '0.01';

sub generate {
    my ($package,$info,@items) = @_;
    
    my $t = $info->{template} || Template->new({
        POST_CHOMP => 1,
        DEBUG => 1,
    });
    
    my $r = \my $result;
    $t->process(sprintf( 'templates/%s/imagestream.html', $info->{theme}),
       { info => $info, items => \@items },
       $r)
       or die "Error while generating HTML: " . $t->error;
    $result
};

1;