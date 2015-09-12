package App::ImageStream::Template::Provider;
use strict;
use parent 'Template::Provider';

sub _init {
    my( $class, %options ) = @_;
    my $theme = delete $options{ theme }
        or die "Need a valid theme for the files";
    my $self = $class->SUPER::new( %options );
    $self->{theme} = $theme;
};

sub process {
    my () = @_;
    my $content = $self->{theme}->get_content(...);
    $self->SUPER::process( @_ );
};

1;