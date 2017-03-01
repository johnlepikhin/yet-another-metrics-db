#!/usr/bin/perl

my $fifo = '/tmp/perl-metrics.fifo';

open $out, '>', $fifo || die "cannot open fifo: $fifo: $?";

print $out "METRICS 1\n";

my $count = 0;
my $count_R = 0;
my $count_D = 0;
my $max_RSS = 0;
foreach my $file (grep { /\/\d+$/ } </proc/*>) {
    open $in, "$file/status" || next;

    while (<$in>) {
        $count++;
        if (($k, $v) = $_ =~ /([^:]+):\s+(.+)/) {
            if ($k eq 'State') {
                if ($v =~ /^R/) {
                    $count_R++;
                } elsif ($v =~ /^D/) {
                    $count_D++;
                }
            } elsif ($k eq 'VmRSS') {
                ($rss) = $v =~ /^(\d+)/;
                $max_RSS = $rss if $rss > $max_RSS;
            }
        }
    }
    close $in;
}

print "value processes/count $count\n";
print "value processes/count-status-R $count_R\n";
print "value processes/count-status-D $count_D\n";
print "value processes/max-RSS $max_RSS\n";

close $out;
