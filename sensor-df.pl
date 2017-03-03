#!/usr/bin/perl

use Sensor;
use strict;
use warnings;

my %values;

sub add($$) {
    my $key = shift;
    my $value = shift;

    $values{$key}{value} = $value;
    $values{$key}{datatype} = 'uint';
    $values{$key}{sensor_options}{output_value_filter} = 'skip-zero';
}

sub process ($$) {
    my $in = shift;
    my $prefix = shift;

    <$in>;

    while (<$in>) {
        chomp;
        my @f = split /\s+/;
        next if @f < 6;

        add("df/used/$prefix-$f[5]", $f[2]);
        add("df/available/$prefix-$f[5]", $f[3]);
    }
}

open my $in, '-|', 'df -m -P -l' || die "cannot open df output: $?";
process ($in, 'mbytes');
close $in;

open $in, '-|', 'df -i -P -l' || die "cannot open df output: $?";
process ($in, 'inodes');
close $in;

my $config = Sensor::parse_opts();

Sensor::safe_save($config, \%values);
