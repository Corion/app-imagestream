package App::ImageStream::List::RSS;
use XML::RSS::SimpleGen ();

use vars qw($VERSION);
$VERSION = '0.04';

sub feed {
    my ($class,$feed_data,$data) = @_;
    my $rss = XML::RSS::SimpleGen->new( $feed_data->{base}, $feed_data->{title} );
    $rss->language('en');
    for my $item (@$data) {
        my $enc_url = URI::Escape::uri_escape($item->{module});
        $rss->item( 
            <url>,
            <title>,
            <text>,
        );
    };
    $rss->daily;
    $rss;
};

