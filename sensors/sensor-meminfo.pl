#!/usr/bin/perl

use lib '../lib';
use Sensor;
use strict;
use warnings;

open my $in, '/proc/meminfo' || die "cannot open /proc/meminfo: $?";

my %values;
while (<$in>) {
    next if !/([^:]+):\s+(\d+)/;
    my $key = "meminfo/$1";
    $values{$key}{value} = $2;
    $values{$key}{datatype} = 'uint';
    $values{$key}{sensor_options}{output_value_filter} = 'skip-zero';
}

close $in;

my $config = Sensor::parse_opts();

Sensor::safe_save($config, \%values);
