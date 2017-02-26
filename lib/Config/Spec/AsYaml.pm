package Config::Spec::AsYaml;
use strict;
use vars qw(@ISA @EXPORT_OK);
use Exporter 'import';
@EXPORT_OK = qw(as_yaml);
use Carp qw(croak);
use YAML::Dumper;
use Scalar::Utils 'dclone';

=head1 NAME

Config::Spec::AsYaml - convert a schema to yaml

=head1 SYNOPSIS

    package My::App::Config;
    use strict;
    use vars qw($raw_config %items);
    use Config::Spec::FromPod 'parse_pod_config';
    use Config::Spec::AsYaml 'as_yaml';
    
    my $raw_config = <<'=cut';
    
    =head1 CONFIGURATION

    =head2 C<< output DIR >>

    =for config
        repeat  => 1,
        default => '/tmp',
    
    Allows you to specify the output directory into which the
    widgets get stored.
    
    =cut

    my %schema = parse_pod_config( $config_raw );
    print as_yaml(\%schema, $config);
    
    1;

=head1 RATIONALE

This module allows you to generate a default configuration file as
an example for customization by the user.

=cut

sub as_yaml {
    my($spec, $config) = @_;
    
    my $target = dclone( $spec );
    # Map the single elements back to scalars
    for my $item ( %$target ) {
        if( $item->{repeat}
    };
    
    return YAML::Dumper->new->dump( $target );
};

1;