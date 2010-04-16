package App::ImageStream::List::RSS;
use XML::RSS::SimpleGen ();

use vars qw($VERSION);
$VERSION = '0.01';

sub generate {
    my ($class,$feed_data,@data) = @_;
    my $rss = XML::RSS::SimpleGen->new( $feed_data->{base}, $feed_data->{title} );
    $rss->language('en');
    for my $item (@data) {
        my $url_large = join "/", 
                          $base_url,
                          $image->{sizes}->{640}->{name}->basename
                        ;
        my $url_thumb = join "/", 
                          $base_url,
                          $image->{sizes}->{160}->{name}->basename
                        ;
        my $title = $image->{title} || $image->{file}->basename;
        my $html = <<HTML; # encode_entities(<<HTML);
<p>$info->{author} hat ein Bild ver&ouml;ffentlicht:</p>
<p><a href="$url_large" title="$title"><img src="$url_thumb" width="$image->{sizes}->{160}->{width}" height="$image->{sizes}->{160}->{height}" alt="$title" /></a></p>
HTML
        
        $rss->item( 
            $url_large,
            $title,
            $html,
        );
    };
    $rss->daily;
    $rss;
};

