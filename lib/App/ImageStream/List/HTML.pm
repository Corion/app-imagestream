package App::ImageStream::List::HTML;
use strict;
use Template;

use vars qw($VERSION);
$VERSION = '0.01';

sub create {
    my ($package,$info,@items) = @_;
    $info ||= {};
    $info->{atom_feed} ||= 'atom';
    $info->{rss_feed}  ||= 'rss';
    $info->{title}     ||= 'My images';
    my $r = \my $result;
    $info->{cpanr}->output_sql_template({ items => \@items },'published.tmpl',$info,$r);
    $r
};

1;