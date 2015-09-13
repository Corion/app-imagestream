package App::ImageStream::Template::Provider;
use strict;
use parent 'Template::Provider';

sub _init {
    my( $class, $options ) = @_;
    my $theme = delete $options->{ theme }
        or die "Need a valid theme for the files";
    my $self = $class->SUPER::_init( $options );
    $self->{theme} = $theme;
};

sub _template_modified {
    my ($self,$path) = @_;
    # we fake this by always returning a fresh timestamp so no caching here
    return time
}

sub _template_content {
    my ($self,$path) = @_;
    my $content = $self->{theme}->get_content($path);
    if( wantarray ) {
        return ($content,'',time);
    } else {
        return $content
    }
};

1;