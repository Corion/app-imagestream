package App::ImageStream::Config::DSL;
use strict;
use Path::Class;

=head1 NAME

App::ImageStream::Config::DSL - create a DSL from a config spec

=cut

sub parse_config {
    my ($package,$spec,$config_data,$config_source) = @_;
    $config_source ||= 'configuration';
    
    my $result = {};
    
    for my $item (values %$spec) {
        my $n = $item->{name};
        my $fetch;
        $result->{$n} = [];
        if (0 == $item->{arg_count}) {
            $fetch = sub() { push @{ $result->{$n}}, 1; };
        } elsif (1 == $item->{arg_count}) {
            $fetch = sub($) { push @{ $result->{$n} }, @_; };
        } elsif (2 == $item->{arg_count}) {
            $fetch = sub($$) { push @{ $result->{$n} }, [@_]; };
        } else {
            $fetch = sub($;) { push @{ $result->{$n}}, [@_]; };
        };
        no strict 'refs';
        local *{$n} = $fetch;
    };
    
    my $ok = eval "package " . __PACKAGE__ . ";\n#line $config_source#1\n$config_data\n;1";
    my $err = $@;
    
    if ($ok) {
        return $result
    } else {
        warn $err;
        return
    };
};

sub parse_config_file {
    my ($package,$spec,$fn) = @_;
    my $file = file($fn);
    $package->parse_config($spec,$file->slurp,$fn);
};

=for later

# Configuration DSL
sub collect($) {
    push @collect, @_;
};

sub reject($) {
    push @reject, @_;
};

sub prefer($$) {
    push @preferred, [ $_[0], $_[1] ];
};

sub output($) {
    $output_directory = shift;
};

sub minimum($) {
    $minimum = shift;
};

sub size($) {
    push @sizes, shift;
};

sub exclude_tag($;$$$$$$$) {
    @exclude_tags{map uc @_} = (undef) x @_;
}

sub cutoff($) {
    $cutoff = time - 24*3600*shift;
}

=cut

1;