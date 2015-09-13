package App::ImageStream::List::Manifest;
use strict;
use HTML5::Manifest::Writer 'generate_manifest';
use vars qw($VERSION);
$VERSION = '0.01';

sub generate {
    my ($package,$info,$template,$theme,@items) = @_;
    # Note: We expect both here, filenames and ImageStream::Images...
    
    my @entries;
    my $base_url = $info->{base}     || 'http://datenzoo.de/image_stream';

    for my $item (@items) {
        if( ! ref $item) {
            # $item better be a relative URL
            push @entries, join "/", $base_url, $item;
        } else {
            for my $size (sort keys %{ $item->{sizes}}) {
                my $url = join "/", 
                              $base_url,
                              $item->{sizes}->{$size}->{name}->basename
                            ;
                push @entries, $url;
            };
        };
    };
    return generate_manifest(
        cache => \@entries,
        network => []
    );
};

