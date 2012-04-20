# -*- mode: perl; c-basic-offset: 4; indent-tabs-mode: nil; -*-

use 5.006; #weaken
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile1(
    MIN_PERL_VERSION => '5.008',
    META_MERGE => {
        resources => {
            repository => 'http://github.com/Corion/app-imagestream',
        },
    },
    BUILD_REQUIRES => {
                        'Exporter' => 5, # need 'import' feature
    },
    'NAME'          => 'App::ImageStream',
    'LICENSE'       => 'perl',
    'VERSION_FROM'  => 'lib/App/ImageStream.pm', # finds $VERSION
    'PREREQ_PM'     => { #'threads' => 1.81, # To defend against "invalid value for shared scalar"
                         #'Thread::Queue' => 1.81,
                        'Decision::Depends' => 0,
                        'Path::Class' => 0.23, # fixes ->slurp on Win32
                        'XML::Atom::SimpleFeed' => 0,
                        'XML::RSS::SimpleGen' => 0,
                        'Imager' => 0,
                        'Image::ExifTool' => 0,
                        'Image::Thumbnail' => 0,
                        'Image::Info' => 0,
                        'DateTime' => 0,
                        'File::HomeDir' => 0, # for the config system
                        'List::Util' => 0, # for reduce()
                        'Text::Unidecode' => 0, # to create sanitized URLs
                      }, # e.g., Module::Name => 1.1
    ABSTRACT_FROM   => 'lib/App/ImageStream.pm', # retrieve abstract from module
    AUTHOR          => 'Max Maischein <corion@cpan.org>',
);

1;

sub WriteMakefile1 {  #Written by Alexandr Ciornii, version 0.21. Added by eumm-upgrade.
    my %params=@_;
    my $eumm_version=$ExtUtils::MakeMaker::VERSION;
    $eumm_version=eval $eumm_version;
    die "EXTRA_META is deprecated" if exists $params{EXTRA_META};
    die "License not specified" if not exists $params{LICENSE};
    if ($params{BUILD_REQUIRES} and $eumm_version < 6.5503) {
        #EUMM 6.5502 has problems with BUILD_REQUIRES
        $params{PREREQ_PM}={ %{$params{PREREQ_PM} || {}} , %{$params{BUILD_REQUIRES}} };
        delete $params{BUILD_REQUIRES};
    }
    delete $params{CONFIGURE_REQUIRES} if $eumm_version < 6.52;
    delete $params{MIN_PERL_VERSION} if $eumm_version < 6.48;
    delete $params{META_MERGE} if $eumm_version < 6.46;
    delete $params{META_ADD} if $eumm_version < 6.46;
    delete $params{LICENSE} if $eumm_version < 6.31;
    delete $params{AUTHOR} if $] < 5.005;
    delete $params{ABSTRACT_FROM} if $] < 5.005;
    delete $params{BINARY_LOCATION} if $] < 5.005;
    
    WriteMakefile(%params);
}
