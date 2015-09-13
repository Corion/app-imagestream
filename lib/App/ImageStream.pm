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
    
    # @generated_files will contain both images and additionally
    # generated or copied files
    my @generated_files = @selected;
    
    my %seen;
    for my $format (qw(atom rss)) {
        my $entry = "imagestream.$format";
        my $template;
        if ($theme->contains_file($entry)) {
            $template = $theme->get_content($entry);
        };
        $seen{ $entry }++;
        my $target = file( $output, $entry );
        App::ImageStream::List->create(
            $format => $target,
            $template,
            $cfg,
            @selected
        );
        push @generated_files, $target;
    }

    for my $entry (@{ $cfg->{template_file}}) {
        warn "Filling in template for '$entry' (html)";
        my $template;
        if ($theme->contains_file($entry)) {
            $template = $theme->get_content($entry);
        };
        $seen{ $entry }++;
        my $target = file( $output, $entry );
        App::ImageStream::List->create(
            'html' => $target,
            $template,
            $theme,
            $cfg,
            @selected
        );
        push @generated_files, $target;
    }

    # copy all other files from the theme
    for my $file ($theme->list_files) {
        next
            if $seen{ $file };
        my $target = file($output, $file );
        push @generated_files, $target;
        #status 3, "Copying $file";
        $theme->extract_file($file, $target);
    };
    
    # Generate a HTML5 manifest if that's wanted
    if( my $manifest_file = $cfg->{manifest}->[0]) {
        my $target = file($output, $manifest_file );
        App::ImageStream::List->create(
            'manifest' => $target,
            undef,
            $theme,
            $cfg,
            @generated_files
        );
    };
};

1;