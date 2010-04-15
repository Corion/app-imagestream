package App::ImageStream::List::Atom;
use strict;
use XML::Atom::SimpleFeed;
use POSIX qw(strftime);
#use HTML::Entities qw( encode_entities );

use vars qw($VERSION);
$VERSION = '0.01';

sub generate {
    my ($package,$info,@items) = @_;
    
    my $base_url = $info->{base}     || 'http://datenzoo.de/gallery';
    my $feed_url = $info->{feed_url} || "${base_url}/atom";
    
    # XXX This should be done twice, once for $old, once for $new,
    #     or with a s///g to match the two up.
    my $updated  = strftime '%Y-%m-%dT%H:%M:%SZ', gmtime;
    
    #use Data::Dumper;
    #warn Dumper $info;
    my $feed = XML::Atom::SimpleFeed->new(
        title   => $info->{title} || 'My image stream',
        link    => $base_url,
        link    => { rel => 'self', href => $feed_url, },
        author  => $info->{author} || 'A. U. Thor',
        id      => $base_url,
        updated => $updated,
        #%$info,
    );
    for my $image (@items) {
        my $updated = $image->{date_taken} || $updated;
        
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
    
        my @categories = map {;
            category => $_,
        } @{$image->{exif}->{KeyWords}};

        # XXX Here we should link to the HTML page that should ideally center
        # on the image already, using a "#name" link
        
        # Beware: XML::Atom::SimpleFeed uses warnings => fatal,
        # so all warnings within it die.
        $feed->add_entry(
            title     => $image->{title} || $image->{file}->basename,
            link      => { rel => 'alternate',
                           type => "text/html",
                           href => $url_large },
            id        => $url_large,
            #summary   => $image->{review_text} || '',
            content   => { type => "html",
                           content => $html },
            updated   => $updated,
            published => $updated, # XXX split off updated vs. published
            link      => { rel => 'enclosure',
                           type => $image->{mime_type},
                           href => $url_large },
            @categories,
        );
    };
    $feed->as_string;
}

1;