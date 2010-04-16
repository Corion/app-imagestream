package App::ImageStream::List::RSS;
use XML::RSS::SimpleGen ();
use strict;
use vars qw($VERSION);
$VERSION = '0.01';

use Data::Dumper;

sub generate {
    my ($class,$info,@data) = @_;

    my $base_url = $info->{base}     || 'http://datenzoo.de/image_stream';
    my $feed_url = $info->{feed_url} || "${base_url}/rss";
    my $stream_author   = $info->{author} || "A.U. Thor";
    
    my $rss = XML::RSS::SimpleGen->new( $base_url, $info->{title} );
    $rss->language('en');
    for my $item (@data) {
        my $url_large = join "/", 
                          $base_url,
                          $item->{sizes}->{640}->{name}->basename
                        ;
        my $url_thumb = join "/", 
                          $base_url,
                          $item->{sizes}->{160}->{name}->basename
                        ;
        my $title = $item->title;
        my $author = $item->author || $stream_author;
        my $html = <<HTML; # encode_entities(<<HTML);
$author hat ein Bild ver&ouml;ffentlicht:
<a href="$url_large" title="$title"><img src="$url_thumb" width="$item->{sizes}->{160}->{width}" height="$item->{sizes}->{160}->{height}" alt="$title" /></a>
HTML
        
        $rss->item( 
            $url_large,
            $title,
            \$html, # reference means "no HTML removal"
        );
    };
    $rss->daily;
    return $rss->as_string;
};

