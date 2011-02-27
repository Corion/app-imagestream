package Archive::Dir;
use strict;
use Carp qw(croak);
use Path::Class;
use vars qw($VERSION);
$VERSION = '0.01';

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

sub list_files {
    my ($self,$properties) = @_;
    croak "Listing properties is not (yet) implemented"
        if $properties;
    my @files;
    $self->directory->recurse(callback => sub { push @files, $_[0] if !$_[0]->is_dir});
    map { $_->relative( $self->directory ) } @files
}

sub extract_file {
    my ($self,$file,$target) = @_;
    if ($self->contains_file( $file )) {
        open my $fh, '>', $target
            or croak "Couldn't create '$target': $!";
        binmode $fh;
        print {$fh} $self->get_content($file);
    } else {
        croak "'$file' is not contained in '" . $self->directory . "'";
    };
};

1;