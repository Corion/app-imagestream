# Read command line
# Merge items from %ENV
# Merge items from config file ./app.cfg
# Merge items from user config file ~/app.cfg
# Merge items from global config file /etc/app.cfg
# Merge application defaults from ::Items.pm
package Config::Collect;
use strict;
use Hash::Merge;
use File::Homedir;
use Path::Class qw(file);
use App::ImageStream::Config::DSL;
use App::ImageStream::Config::Getopt;
use App::ImageStream::Config::Defaults;
use List::Util qw(reduce);
use vars qw( $merge $VERSION);
$VERSION = '0.01';

use Data::Dumper;
Hash::Merge::specify_behavior(
    {
        'SCALAR' => {
            'SCALAR' => sub { warn Dumper \@_; $_[0] },
            'ARRAY'  => sub { 0+@{$_[0]} ? $_[0] : $_[1] },
            'HASH'   => sub { warn Dumper \@_; $_[0] },
        },
        'ARRAY' => {
            'SCALAR' => sub { warn Dumper \@_; $_[0] },
            'ARRAY'  => sub { 0+@{$_[0]} ? $_[0] : $_[1] },
            'HASH'   => sub { warn Dumper \@_; $_[0] },
        },
        'HASH' => {
            'SCALAR' => sub { warn Dumper \@_; $_[0] },
            'ARRAY'  => sub { 0+@{$_[0]} ? $_[0] : $_[1] },
            'HASH'   => sub { Hash::Merge::_merge_hashes( $_[0], $_[1] ) },
        },
    }
    => 'KEEP_LEFT'
);

$merge = Hash::Merge->new('KEEP_LEFT');

=head2 C<< ->collect >>

=item *

C<config_file> - arrayref of configuration files to load. The order
is most specific to least specific.

=cut

sub collect {
    my ($class, $struct, %opts) = @_;
    $opts{ getopt } ||= {};

    # Least specific to most specific?!
    $opts{ config_default } ||= file($0 . ".cfg")->basename;
    $opts{ config_file } ||= $opts{ config_default };
    if (! ref $opts{ config_file }) {
        $opts{ config_file } = [$opts{ config_file }]
    };

    # Order: Most specific to least specific
    $opts{ config_dirs } ||= ['.',File::HomeDir->my_data,'/etc'];

    # now, try to also load other config files specifying additional defaults
    # Only those we can read
    push @{ $opts{ config_file }}, map {
             my $f = file($_, $opts{ config_default });
             -r $f ? $f : ()
    } @{ $opts{ config_dirs }};
    
    
    # XXX Do we want to be able to add more things, and if so, where?
    # Maybe a list of files, instead of just config_file
    # Also, how do we communicate upwards which items we actually used?
    
    my @options;
    my @config_files;
    my ($ok,$opt_commandline) = App::ImageStream::Config::Getopt->get_options(
        $struct,
        'c|config:s' => \@config_files,
        %{ $opts{ getopt }},
    );
    push @options, $opt_commandline;
    # XXX Should this just call Pod::Usage?!

    # XXX Parse %ENV here

    if (! @config_files) {
        @config_files = @{ $opts{ config_file } };
    };
    for my $config_file (@config_files) {
        if( ref $config_file eq 'SCALAR') {
            push @options, App::ImageStream::Config::DSL->parse_config(
                \%App::ImageStream::Config::Items::items,
                $$config_file,
            );
        } else {
            push @options, App::ImageStream::Config::DSL->parse_config_file(
                \%App::ImageStream::Config::Items::items,
                $config_file,
            );
        };
    };

    push @options, App::ImageStream::Config::Defaults->parse_config(
        \%App::ImageStream::Config::Items::items,
    );
    push @options, { _meta => { loaded_files => \@config_files } };

    reduce { $merge->merge( $a, $b ) } {}, @options;
};

1;

=head1 SEE ALSO

L<Config::Onion> - another config loader with a similar approach but a fixed
hierarchy of layers. It is missing the "environment" layer and also doesn't
allow for arbitrary config file formats.

=cut