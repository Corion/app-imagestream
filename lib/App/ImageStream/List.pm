package App::ImageStream::List;
use strict;
use App::ImageStream::List::Atom;
use App::ImageStream::List::HTML;
use App::ImageStream::List::RSS;
use Path::Class;
use POSIX qw(strftime);

use vars qw($VERSION);
$VERSION = '0.01';

use vars '%types';

%types = (
    'atom' => 'App::ImageStream::List::Atom',
    'rss'  => 'App::ImageStream::List::RSS',
    'html' => 'App::ImageStream::List::HTML',
    'manifest' => 'App::ImageStream::List::Manifest',
);

=head2 C<< ->create TYPE, FILE, ITEMS >>

Creates the new file if it is different
from the old file.

=cut

sub create {
    my ($package,$type, $file, $template, $config, @items) = @_;
    my $old = '';
    
    $old = file($file)->slurp(iomode => '<:raw')
        if (-f $file);
    
    my $base_url = $config->{ base }->[0];
    if( !$base_url ) {
        $base_url = $config->{ canonical_url }->[0];
        $base_url =~ s!/[^/]+$!/!;
    };
    my $feed_url = "${base_url}/" . $file->basename;
    $feed_url =~ s/\.(\w+)$//;
    my $updated  = strftime '%Y-%m-%dT%H:%M:%SZ', gmtime;
    my $feeds = {
        atom => "$feed_url.atom",
        rss  => "$feed_url.rss",
        html => "$feed_url.html",
        manifest => "$feed_url.manifest",
    };
    my $theme = $config->{theme}->[0];
    
    my $feedinfo = {
        title   => $config->{title}->[0] || 'My image feed',
        link    => { rel => 'self', href => $feed_url, },
        author  => $config->{author}->[0] || 'A. U. Thor',
        id      => $base_url,
        base    => $base_url,
        feed_url => "$base_url/" . $file->basename,
        canonical => $config->{ canonical_url }->[0],
        hero_image => $config->{hero_image}->[0],
        updated => $updated,
        feeds   => $feeds,
        theme   => $theme,
        about   => "App::ImageStream $VERSION",
    };
    
    my $generator = $types{$type};
    my $new = $generator->generate($feedinfo, $template, @items);
    
    if ($old ne $new) {
        open my $out, '>', $file
            or die "Couldn't create '$file': $!";
        binmode $out;
        print {$out} $new;
    }
}

1;