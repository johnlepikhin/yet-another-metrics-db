#!/usr/bin/perl

my $fifo = '/tmp/perl-metrics.fifo';

open $out, '>', $fifo || die "cannot open fifo: $fifo: $?";
open $in, '/proc/meminfo' || die "cannot open /proc/meminfo: $?";

print $out "METRICS 1\n";

while (<$in>) {
    next if !/([^:]+):\s+(\d+)/;
    print $out "value meminfo/$1 $2\n";
}

close $in;
close $out;
