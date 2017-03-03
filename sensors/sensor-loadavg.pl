#!/usr/bin/perl

use lib '../lib';
use Sensor;
use strict;
use warnings;

open my $in, '/proc/loadavg' || die "cannot open /proc/loadavg: $?";
my $la = (split /\s+/, <$in>)[0];
close $in;

my %values;
$values{'load-avg1-mult100'}{value} = int($la*100);
$values{'load-avg1-mult100'}{datatype} = 'uint';

my $config = Sensor::parse_opts();

Sensor::safe_save($config, \%values);
