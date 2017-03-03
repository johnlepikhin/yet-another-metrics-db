#!/usr/bin/perl

use Sensor;
use strict;
use warnings;

my $count = 0;
my $count_R = 0;
my $count_D = 0;
my $max_RSS = 0;
foreach my $file (grep { /\/\d+$/ } </proc/*>) {
    open my $in, "$file/status" || next;

    while (<$in>) {
        $count++;
        if (my ($k, $v) = $_ =~ /([^:]+):\s+(.+)/) {
            if ($k eq 'State') {
                if ($v =~ /^R/) {
                    $count_R++;
                } elsif ($v =~ /^D/) {
                    $count_D++;
                }
            } elsif ($k eq 'VmRSS') {
                my ($rss) = $v =~ /^(\d+)/;
                $max_RSS = $rss if $rss > $max_RSS;
            }
        }
    }
    close $in;
}

my %values;

$values{'processes/count'}{value} = $count;
$values{'processes/count'}{datatype} = 'uint';

$values{'processes/count-status-R'}{value} = $count_R;
$values{'processes/count-status-R'}{datatype} = 'uint';

$values{'processes/count-status-D'}{value} = $count_D;
$values{'processes/count-status-D'}{datatype} = 'uint';

$values{'processes/max-RSS'}{value} = $max_RSS;
$values{'processes/max-RSS'}{datatype} = 'uint';

my $config = Sensor::parse_opts();

Sensor::safe_save($config, \%values);
