package App::ImageStream::List::Atom;
use strict;
use XML::Atom::SimpleFeed;
use POSIX qw(strftime);

use vars qw($VERSION);
$VERSION = '0.01';

sub generate {
    my ($package,$info,@items) = @_;
    
    my $base_url = $info->{base}     || 'http://corion.net/gallery';
    my $feed_url = $info->{feed_url} || "${base_url}/atom";
    $info->{title} ||= 'My image feed';
    my $author   = $info->{author}   || 'A.U. Thor';
    my $updated = strftime '%Y-%m-%dT%H:%M:%SZ', gmtime;
    
    my $feed = XML::Atom::SimpleFeed->new(
        title   => $title,
        link    => $base_url,
        link    => { rel => 'self', href => $feed_url, },
        author  => $author,
        id      => $base_url,
        updated => $updated,
        %info,
    );
    for my $image (@items) {
        my $updated = $item->{date_taken};
        $updated =~ s/ /T/;
        $updated .= "Z";
        
        my @categories = map {
            category => $_,
        } @info->{exif}->{KeyWords};

        my $enc_url = URI::Escape::uri_escape($item->{module});
        
        # XXX Here we should link to the HTML page that should ideally center
        # on the image already, using a "#name" link
        my $target = join("/",$base_url, $image->{target});
        
        # Beware: XML::Atom::SimpleFeed uses warnings => fatal,
        # so all warnings within it die.
        $feed->add_entry(
            title     => $item->{title},
            link      => $target,
            id        => $target,
            summary   => $item->{review_text},
            content   => 'HTML',
            updated   => $updated,
            @categories,
        );
    };
    $atom->as_string;
}

1;