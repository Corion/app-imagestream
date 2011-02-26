package Archive::Dir;
use strict;
use Path::Class;

=head1 NAME

Archive::Dir - a directory with an API like an Archive::Tar

=head1 SYNOPSIS

    my $ar = Archive::Dir->new('foo');

=cut

sub new {
    my ($class, $directory) = @_;
    my $self = {
        directory => dir($directory),
    };
    bless $self => $class;
    $self
};

sub directory {
    $_[0]->{directory}
};

sub contains_file {
    -f $_[0]->directory->file($_[1])
};

sub get_content {
    $_[0]->directory->file($_[1])->slurp(iomode => '<:raw');
};

1;