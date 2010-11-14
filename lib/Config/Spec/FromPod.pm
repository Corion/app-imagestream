package Config::Spec::FromPod;
use strict;
use vars qw(@ISA @EXPORT_OK);
require Exporter;
@ISA='Exporter';
@EXPORT_OK = qw(parse_pod_config);
use Carp qw(croak);

=head1 NAME

Config::FromPod - generate configuration metadata from well-formatted Pod

=head1 SYNOPSIS

    package My::App::Config;
    use strict;
    use vars qw($raw_config %items);
    
    my $raw_config = <<'=cut';
    
    =head1 CONFIGURATION

    =head2 C<< output DIR >>

    =for config
        repeat  => 1,
        default => '/tmp',
    
    Allows you to specify the output directory into which the
    widgets get stored.
    
    =cut

    %items = parse_pod_config( $config_raw );
    
    # %items is now usable for ::DSL or ::Getopt
    #use Data::Dumper;
    #warn Dumper %items;
    
    1;

=head1 RATIONALE

This module forces you to write your config file format documentation
as pod and directly generates the metadata structure from the documentation.
This means that your documentation will not go out of sync with the code
that uses it.

=head1 FORMAT

A minimal config entry looks like this

  =head2 C<< item ITEM >>
  
  Label
  
  Item description

This will result in the following data structure:

  ITEM => {
      name =>  'ITEM',
      label => 'Label',
      spec  => XXX,
      desc  => 'Item description',
  }

A full-blown config entry looks like this:

=cut

sub parse_pod_config {
    map {
        my %options;
        if (s/^=for config\s*?\n(.*?)\n\n//ms) {
            # Ugh. This would maybe better be a regex to fish out
            # the relevant part instead of C<eval>.
            %options = eval $1;
            croak $@ if $@;
            #warn ">>$spec<<";
            #while ($spec =~ s/^\s+(\w+)\s+=>\s*(\S+.*?)\s*(,\s*?\n|,$)//) {
            #    $options{ $1 } = $2;
            #    warn "$1 => $2\n";
            #};
            #warn "Malformed option spec (remaining '$spec' in =for config block)"
            #    if $spec =~ /\S/;
        };
        if (! /^=head2\s+C<<\s+(\w+) (.*)\s+>>\s+(\w.*?)\n(.*)$/ms) {
            if (! /^=head2\s+C<<\s+(\w+) (.*)\s+>>/ms) {
                croak "Malformed config item header '$_'";
                
            } elsif(! /^=head2\s+C<<\s+(\w+) (.*)\s+>>\s+(\w.*?)/ms) {
                croak "Malformed config item label in '$_'";
                
            } else {
                croak "Malformed config item '$_'";
            };
        };
        my ($name,$spec,$label,$desc) = ($1,$2,$3,$4);        
        
        my $count =()= ($spec =~ m/,/g);
        $count++;
        my $res = {
            name      => $name,
            spec      => $spec,
            label     => $label,
            desc      => $desc,
            arg_count => $count,
            default   => undef,
            repeat    => undef,
            %options
        };
        
        for (qw(name spec label desc)) {
            $res->{$_} =~ s/^\s+//;
            $res->{$_} =~ s/\s+$//mg;
            $res->{$_} =~ s/\r\n/\n/g;
        };
        
        $name => $res,
    }
    grep /^=head2/, 
    split /(?==head2)/,
    shift
};

1;