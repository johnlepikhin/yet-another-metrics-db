#!/usr/bin/perl

use Time::HiRes qw(setitimer ITIMER_REAL);

use warnings;
use strict;

use lib 'lib';
use Getopt::Long;
use Pod::Usage;
use Config::Metrics;
use Storage;
use IO::Socket::UNIX;

require 5.008001;

use POSIX qw(mkfifo);

sub get_client ($) {
    my $config = shift;

    if (!exists $config->{general}->{server_socket}) {
        my $sock = $config->{general}->{values}->{listen};

        unlink $sock if length $sock > 0 && -S $sock;

        my $server = IO::Socket::UNIX->new(
            Type => SOCK_STREAM(),
            Local => $sock,
            Listen => 1,
            ) || die "cannot listen socket $sock: $!";

        $config->{general}->{server_socket} = $server;
    }
    
    my $client;
    while (1) {
        $client = $config->{general}->{server_socket}->accept();
        return $client if $client;
        die "cannot accept client: $?" if (!$!{EINTR});
    };
}

sub process_client($$$) {
    my $config = shift;
    my $fh = shift;
    my $current = shift;

    # check protocol and version
    my $first = <$fh>;
    goto release_fh_return if !defined $first;

    chomp $first;
    if ($first !~ /^METRICS (\d+)/ || $1 > 1) {
        goto release_fh_return;
    }
    
    while (<$fh>) {
        goto release_fh_return if !defined $_;
        
        chomp;

        if (my ($key, $value) = $_ =~ /^value\s+(\S+)\s+(.*)/i) {
            if (exists $config->{"metrics:$key"}) {
                my $agregate_fn = $config->{"metrics:$key"}->{values}->{agregate_fn};
                if ($agregate_fn eq 'take-last') {
                    $current->{$key} = $value;
                } elsif ($agregate_fn eq 'numeric-diff') {
                    $current->{$key}->{current} = $value;
                }
            }
        } elsif (/^exit$/i) {
            exit 0;
        }
    }

  release_fh_return:
    close $fh;
}

sub clean_current($$) {
    my $config = shift;
    my $current = shift;

    foreach (keys %$current) {
        if (exists $config->{"metrics:$_"}) {
            my $agregate_fn = $config->{"metrics:$_"}->{values}->{agregate_fn};
            if ($agregate_fn eq 'take-last') {
                delete $current->{$_};
            } elsif ($agregate_fn eq 'numeric-diff') {
                if (!exists $current->{$_}->{prev}) {
                    delete $current->{$_};
                }
            }
        }
    }
}

sub loop_fifo($) {
    my $config = shift;

    my %current;

    $SIG{ALRM} = sub {
        Config::Metrics::update_config_if_changed($config);
        Storage::save_current($config, \%current);
        clean_current($config, \%current);
    };

    my $tick_size = $config->{general}->{values}->{tick_size_ms}/1000;
    setitimer(ITIMER_REAL, $tick_size, $tick_size);
    
    while (1) {
        my $client = get_client($config);
        process_client($config, $client, \%current);
    }
}

my $opt_config_path;
my $opt_help;
my $opt_man;

GetOptions('config|c=s' => \$opt_config_path
           , 'help|?' => \$opt_help
           , 'man|?' => \$opt_man
    );

pod2usage(-exitval => 0, -verbose => 2, -input => \*DATA) if $opt_man;
pod2usage(-exitval => 0, -verbose => 1, -input => \*DATA) if $opt_help;

sub fatal ($) {
    pod2usage(-msg => $_[0], -exitval => 1, -verbose => 1, -input => \*DATA);
}

if (!defined $opt_config_path) {
    fatal "--config is mandatory";
}

my $config = Config::Metrics::read($opt_config_path) || die Config::IniPlain::errstr();

loop_fifo($config);

__DATA__

=head1 NAME

collect-metrics - Collect metrics and save to database

=head1 SYNOPSIS

dump-metrics --config=<config file>

=head1 OPTIONS

=over 8

=item B<--config=<...>>

Path to configuration ini file

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
