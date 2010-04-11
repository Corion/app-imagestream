package App::ImageStream::List;
use strict;
use App::ImageStream::List::Atom;
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
    my ($type, $file,@items) = @_;
    my $old = file($file)->slurp;
    
    my $generator = $types{$type};
    my $new = $generator->generate(@items);
    
    if ($old ne $new) {
        open my $out, '>', $file
            or die "Couldn't create '$file': $!";
        binmode $out;
        print {$out} $new;
    }
}

1;