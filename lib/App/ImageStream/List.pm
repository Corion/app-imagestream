package App::ImageStream::List;
use strict;
use App::ImageStream::List::Atom;
use App::ImageStream::List::RSS;
use Path::Class;

use vars qw($VERSION);
$VERSION = '0.01';

use vars '%types';

%types = (
    'atom' => 'App::ImageStream::List::Atom',
    'rss'  => 'App::ImageStream::List::RSS',
    'html' => 'App::ImageStream::List::HTML',
);

=head2 C<< ->create TYPE, FILE, ITEMS >>

Creates the new file if it is different
from the old file.

=cut

sub create {
    my ($type, $file, $config, @items) = @_;
    my $old = '';
    
    $old = file($file)->slurp
        if (-f $file);
    
    # XXX Make configurable
    my $base_url = $config->{ base }->[0] || 'http://datenzoo.de/image_stream';
    my $feed_url = "${base_url}/" . $file->basename;
    my $updated  = strftime '%Y-%m-%dT%H:%M:%SZ', gmtime;
    
    my $feedinfo = {
        title   => $config->{title}->[0] || 'My image feed',
        link    => $base_url,
        link    => { rel => 'self', href => $feed_url, },
        author  => $config->{author}->[0] || 'A. U. Thor',
        id      => $base_url,
        base    => $base_url,
        feed_url => "$base_url/" . file($file)->basename,
        updated => $updated,
    };
    
    my $generator = $types{$type};
    my $new = $generator->generate($feedinfo, @items);
    
    if ($old ne $new) {
        open my $out, '>', $file
            or die "Couldn't create '$file': $!";
        binmode $out;
        print {$out} $new;
    }
}

1;