package App::ImageStream::List::RSS;
use XML::RSS::SimpleGen ();
use HTML::Entities qw(encode_entities);
use strict;
use vars qw($VERSION);
$VERSION = '0.01';

use Data::Dumper;

sub generate {
    my ($package,$info,$template,$theme,@items) = @_;

    my $base_url = $info->{base}     || 'http://datenzoo.de/image_stream';
    my $feed_url = $info->{feed_url} || "${base_url}/rss";
    my $stream_author   = $info->{author} || "A.U. Thor";
    
    my $rss = XML::RSS::SimpleGen->new( $base_url, $info->{title} );
    $rss->language('en');
    for my $item (@items) {
        my $url_large = join "/", 
                          $base_url,
                          $item->{sizes}->{medium}->{name}->basename
                        ;
        my $url_thumb = join "/", 
                          $base_url,
                          $item->{sizes}->{thumbnail}->{name}->basename
                        ;
        my $title = $item->title;
        my $author = $item->author || $stream_author;
        my $html = encode_entities(<<HTML);
$author hat ein Bild ver&ouml;ffentlicht:
<a href="$url_large" title="$title"><img src="$url_thumb" width="$item->{sizes}->{thumbnail}->{width}" height="$item->{sizes}->{thumbnail}->{height}" alt="$title" /></a>
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

