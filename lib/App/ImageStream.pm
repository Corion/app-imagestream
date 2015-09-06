package App::ImageStream;
use strict;
use vars qw($VERSION);
use Archive::Tar;
use Archive::Dir;
use Archive::Merged;
use Path::Class;

=head1 NAME

App::ImageStream - generate a slideshow of recent images from your harddisk

=cut

$VERSION = '0.02';

=head2 C<< ->get_theme $cfg >>

Fetches the theme (a directory or tar archive)
and returns either an L<Archive::Dir> or L<Archive::Tar>
object.

=cut

sub get_theme {
    my ($self,$cfg) = @_;
    my @themes;
    for my $theme (@{$cfg->{theme}}) {
        if (-d "templates/$theme") {
            $theme = Archive::Dir->new("templates/$theme")
        } elsif ($theme =~ /(?:\.tar(\.gz)?|\.tgz)$/i) {
            $theme = Archive::Tar->new("templates/$theme")
        } else {
            die "Can't find theme '$theme'";
        };
        push @themes, $theme;
    };
    
    if( $cfg->{merge_theme} ) {
        push @themes, Archive::Dir->new( $cfg->{merge_theme}->[0] );
    };
    
    my $theme;
    if( @themes > 1 ) {
        $theme = Archive::Merged->new( @themes )
    } else {
        $theme = $themes[0]
    };
    
    $theme
};

sub apply_theme {
    my ($self, $cfg, $theme, $output, @selected) = @_;
    
    my %seen;
    for my $format (qw(atom rss html)) {
        my $entry = "imagestream.$format";
        my $template;
        if ($theme->contains_file($entry)) {
            $template = $theme->get_content($entry);
        };
        $seen{ $entry }++;
        App::ImageStream::List->create(
            $format => file( $output, $entry ),
            $template,
            $cfg,
            @selected
        );
    }

    # copy all other files from the theme
    for my $file ($theme->list_files) {
        next
            if $seen{ $file };
        my $target = file($output, $file );
        #status 3, "Copying $file";
        $theme->extract_file($file, $target);
    };
};

1;