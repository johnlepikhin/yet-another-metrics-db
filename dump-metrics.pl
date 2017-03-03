#!/usr/bin/perl

use warnings;
use strict;

use Getopt::Long;
use Pod::Usage;
use Config::Metrics;
use Storage;

my $opt_config_path;
my $opt_start_date;
my $opt_end_date;
my $opt_help;
my $opt_man;

GetOptions('config|c=s' => \$opt_config_path
           , 'start-timestamp|s=i' => \$opt_start_date
           , 'end-timestamp|e=i' => \$opt_end_date
           , 'help|?' => \$opt_help
           , 'man|?' => \$opt_man
    );


pod2usage(-exitval => 0, -verbose => 2, -input => \*DATA) if $opt_man;
pod2usage(-exitval => 0, -verbose => 1, -input => \*DATA) if $opt_help;

sub fatal ($) {
    pod2usage(-msg => $_[0], -exitval => 1, -verbose => 1, -input => \*DATA);
}

if (!defined $opt_config_path || !defined $opt_start_date || !defined $opt_end_date) {
    fatal "--config, --start-timestamp and --end-timestamp are mandatory";
}

my $config = Config::Metrics::read($opt_config_path) || die Config::IniPlain::errstr();

# sample reading
my $period = Storage::read_period($config, $opt_start_date, $opt_end_date);

foreach my $time (sort keys %$period) {
    foreach my $key (sort keys %{$period->{$time}}) {
        print "$time: $key=$period->{$time}->{$key}\n";
    }
}

__DATA__

=head1 NAME

dump-metrics - Dump data from metrics database

=head1 SYNOPSIS

dump-metrics --config=<config file> --start-timestamp=<N> --end-timestamp=<N>

=head1 OPTIONS

=over 8

=item B<--config=<...>>

Path to configuration ini file

=item B<--start-timestamp=<N>> or B<-s <N>>

Start UNIX timestamp to be extracted

=item B<--end-timestamp=<N>> or B<-e <N>>

End UNIX timestamp to be extracted

=item B<--help>

Print a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

This program dumps data from metrics database in log-like human readable format.

=head1 COPIRIGHT

Evgenii Lepikhin <johnlepikhin@gmail.com>

=cut
