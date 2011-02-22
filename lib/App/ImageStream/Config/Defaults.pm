package App::ImageStream::Config::Defaults;
use strict;
use Path::Class;

=head1 NAME

App::ImageStream::Config::Defaults - use default values from a config spec

=cut

sub parse_config {
    my ($package,$spec,$config_source) = @_;
    $config_source ||= 'default';
    
    my $result = {};
    
    my %handler;
    for my $item (values %$spec) {
        my $n = $item->{name};
        my $v = ref $item->{default} eq 'ARRAY'
                ?   $item->{default}
                : [ $item->{default} ];
        
        # XXX Perform substitutions here?!
        
        $result->{$n} = $v
    };

    return $result
};

1;

__END__

=head1 SEE ALSO

L<App::ImageStream::Config::Items> for the data structure

=cut