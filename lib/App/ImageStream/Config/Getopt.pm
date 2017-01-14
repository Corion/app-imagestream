package App::ImageStream::Config::Getopt;
use strict;
use Getopt::Long qw(GetOptionsFromArray);

=head1 NAME

App::ImageStream::Config::Getopt - get command line options from a spec

=head1 SYNOPSIS

  use App::ImageStream::Config::Items;
  use App::ImageStream::Config::Getopt;
  App::ImageStream::Config::Getopt->get_options(
      \%App::ImageStream::Config::Items::items,
      { # additional command line items
          'c|config:s' => \my @config_files,
      },
      \@ARGV
  ) or die "Bad command line argument(s)";

=cut

sub get_options {
    my ($package,$spec,$additional,$argv) = @_;
    $argv ||= \@main::ARGV;
    
    my %handler;
    my $result;
    my @options;
    for my $item (values %$spec) {
        my $n = $item->{name};
        
        my ($opt,$fetch);
        $result->{$n} = [];
        
        if (0 == $item->{arg_count}) {
            $fetch = sub() { push @{ $result->{$n}}, 1; };
            $opt   = $n;
        } elsif (1 == $item->{arg_count}) {
            $fetch = $result->{$n};
            $opt   = "$n=s";
        } elsif (2 == $item->{arg_count}) {
            $fetch = $result->{$n};
            $opt   = "$n=s{$item->{arg_count}}";
        } else {
            warn "More than one argument is not supported by Getopt, got $item->{arg_count}"
        };
        push @options, $opt => $fetch;
        
        # Also support --foo-bar for option foo_bar
        if( $opt =~ s/_/-/g ) {
            push @options, $opt => $fetch;
        };
    };
    return
        (GetOptionsFromArray($argv, @options), $result);
};

1;

__END__

=head1 SEE ALSO

L<App::ImageStream::Config::Items> for the data structure

=cut