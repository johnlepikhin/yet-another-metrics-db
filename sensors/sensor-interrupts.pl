#!/usr/bin/perl

use lib '../lib';
use Sensor;
use strict;
use warnings;

open my $in, '/proc/interrupts' || die "cannot open /proc/interrupts: $?";

my $cpus = (split /\s+/, <$in>)-1;

my %values;
while (<$in>) {
    chomp;
    
    next if !/^\s*([^:]+):\s+(.+)/;
    my $id = $1;
    my $tail = $2;

    my @fields = split /[\s\t]+/, $tail;
    my $descr = join '_', $id, @fields[$cpus..@fields-1];

    for my $cpu (0..$cpus-1) {
        next if $#fields < $cpu;
        my $key = "interrupt/CPU$cpu:$descr";
        $values{$key}{value} = $fields[$cpu];
        $values{$key}{datatype} = 'int';
        $values{$key}{sensor_options}{output_value_filter} = 'skip-zero';
        $values{$key}{sensor_options}{agregate_fn} = 'numeric-diff';
    }
}

close $in;

my $config = Sensor::parse_opts();

Sensor::safe_save($config, \%values);
