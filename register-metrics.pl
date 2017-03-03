#!/usr/bin/perl

use warnings;
use strict;

use Getopt::Long;
use Pod::Usage;
use Config::Metrics;

my $opt_config_path;
my $opt_name;
my $opt_datatype;
my $opt_agregate_fn;
my $opt_output_value_filter;

my $opt_help;
my $opt_man;

GetOptions('config|c=s' => \$opt_config_path
           , 'name|n=s' => \$opt_name
           , 'datatype|t=s' => \$opt_datatype
           , 'agregate-fn=s' => \$opt_agregate_fn
           , 'output-value-filter=s' => \$opt_output_value_filter
           , 'help|?' => \$opt_help
           , 'man|?' => \$opt_man
    );


pod2usage(-exitval => 0, -verbose => 2, -input => \*DATA) if $opt_man;
pod2usage(-exitval => 0, -verbose => 1, -input => \*DATA) if $opt_help;

sub fatal ($) {
    pod2usage(-msg => $_[0], -exitval => 1, -verbose => 1, -input => \*DATA);
}

if (!defined $opt_config_path || !defined $opt_name || !defined $opt_datatype) {
    fatal "--config, --name and --datatype are mandatory";
}

my $config = Config::Metrics::read($opt_config_path) || die Config::IniPlain::errstr();

my %values;

$values{'agregate_fn'}=$opt_agregate_fn if defined $opt_agregate_fn;
$values{'output_value_filter'}=$opt_output_value_filter if defined $opt_output_value_filter;

Config::Metrics::add_metrics ($config, $opt_name, $opt_datatype, \%values);

__DATA__

=head1 NAME

register-metrics - Add new metrica to configuration file

=head1 SYNOPSIS

register-metrics --config=<config file> --name=<...> --datatype=<..> [optional values]

=head1 OPTIONS

=over 8

=item B<--config=<...>>

Path to configuration ini file

=item B<--name>

Metrica name

=item B<--datatype>

Metrica datatype

=item B<--agregate-fn>

Metrica agregation function

=item B<--output-value-filter>

Filter values before saving

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
