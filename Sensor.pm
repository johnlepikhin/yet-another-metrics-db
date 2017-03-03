package Sensor;

require 5.008001;
use warnings;
use strict;
use Exporter;
use IO::Socket::UNIX;
use Config::Metrics;
use Getopt::Long;
use Pod::Usage;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();

sub save ($$) {
    my $config = shift;
    my $values = shift;

    my $out = IO::Socket::UNIX->new(
        Type => SOCK_STREAM(),
        Peer => $config->{general}->{values}->{listen},
        ) || die "cannot open socket $config->{general}->{values}->{listen}: $?";

    print $out "METRICS 1\n";
    foreach my $name (keys %$values) {
        print $out "value $name $values->{$name}->{value}\n";
    }
    shutdown($out, 1);
    close $out;
}

sub safe_save ($$) {
    my $config = shift;
    my $values = shift;

    foreach my $name (keys %$values) {
        my $options = (exists $values->{$name}->{sensor_options}) ? $values->{$name}->{sensor_options} : undef;
        Config::Metrics::add_metrics($config, $name, $values->{$name}->{datatype}, $options);
    }

    save($config, $values);
}

sub parse_opts () {
    my $opt_config_path;

    my $opt_help;
    my $opt_man;

    GetOptions('config|c=s' => \$opt_config_path
               , 'help|?' => \$opt_help
               , 'man|?' => \$opt_man
        );

    pod2usage(-exitval => 0, -verbose => 2, -input => \*DATA) if $opt_man;
    pod2usage(-exitval => 0, -verbose => 1, -input => \*DATA) if $opt_help;

    if (!defined $opt_config_path) {
        pod2usage(-msg => "--config is mandatory", -exitval => 1, -verbose => 1, -input => \*DATA);
    }

    my $config = Config::Metrics::read($opt_config_path) || die Config::IniPlain::errstr();

    $config;
}

1;

__DATA__

Help message: TODO

=cut
