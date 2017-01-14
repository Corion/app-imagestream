package HTML5::Manifest::Writer;
use strict;
use Exporter 'import';
use vars '@EXPORT_OK';
@EXPORT_OK = ('generate_manifest');

=head1 NAME

HTML5::Manifest::Writer - write a HTML5 manifest file

=head1 SEE ALSO

L<HTML5::Manifest> - generate a manifest from files on disk

=cut

sub generate_manifest {
    my( %options ) = @_;
    
    my @res = ('CACHE MANIFEST','');
    if( $options{ network }) {
        push @res, 'NETWORK:', @{ $options{ network }};
    };
    if( $options{ cache }) {
        push @res, 'CACHE:', @{ $options{ cache }};
    };
    
    return join "\x0a", @res
};

1;