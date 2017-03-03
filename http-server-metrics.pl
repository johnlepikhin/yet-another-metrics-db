#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib';
use HTTP::Daemon;
use HTTP::Status;
use URI::QueryParam;
use Getopt::Long;
use Pod::Usage;
use Config::Metrics;
use Storage;

my $opt_config_path;
my $opt_listen;
my $opt_help;
my $opt_man;

GetOptions('config|c=s' => \$opt_config_path
           , 'listen|l=s' => \$opt_listen
           , 'help|?' => \$opt_help
           , 'man|?' => \$opt_man
    );

pod2usage(-exitval => 0, -verbose => 2, -input => \*DATA) if $opt_man;
pod2usage(-exitval => 0, -verbose => 1, -input => \*DATA) if $opt_help;

sub fatal ($) {
    pod2usage(-msg => $_[0], -exitval => 1, -verbose => 1, -input => \*DATA);
}

if (!defined $opt_config_path || !defined $opt_listen) {
    fatal "--config and --listen are mandatory";
}

my ($address, $port);
if ($opt_listen !~ /(.*):(\d+)$/) {
    fatal "Invalid --llisten: '$opt_listen'";
}
$address = $1;
$port = $2;

my $config = Config::Metrics::read($opt_config_path) || die Config::IniPlain::errstr();

sub send_200($$) {
    my $client = shift;
    my $body = shift;

    my $resp = HTTP::Response->new(200);
    $resp->content($body);
    $client->send_response($resp);
}

sub send_data($$$) {
    my $client = shift;
    my $start = shift;
    my $end = shift;
    
    my $period = Storage::read_period($config, $start, $end);

    my $body = '';
    foreach my $time (sort keys %$period) {
        foreach my $key (keys %{$period->{$time}}) {
            $body .= "$time: $key=$period->{$time}->{$key}\n";

            if (length $body > 10_000_000) {
                $client->send_error(400, "Too big response");
                return;
            }
        }
    }

    send_200($client, $body);
}

my $server = HTTP::Daemon->new(
    LocalAddr => $address,
    LocalPort => $port,
    ReuseAddr => 1,
    ReusePort => 1
    ) || die "Cannot start HTTP server: $!";

print ("Server listens at " . $server->url . "\n");

while (my $client = $server->accept) {
    while (my $req = $client->get_request) {
        my $uri = $req->uri;
        if ($req->method eq 'GET') {
            my $format = $uri->query_param('format') || 'text';
            if ($format ne 'text') {
                $client->send_error(400, "Unknown format= value: $format");
                next;
            }
            
            my $q = $uri->query_param('q');

            if (!defined $q || !$q) {
                $client->send_error(400, "Invalid q= value");
                next;
            }
            
            if ($q eq 'period') {
                my $start = $uri->query_param('start');
                my $end = $uri->query_param('end');

                if (!defined $start || !defined $end || $start > $end) {
                    $client->send_error(400, "Invalid start= or end=");
                    next;
                }

                if ($end - $start > 86400*100) {
                    $client->send_error(400, "Cannot request more than 100 days period");
                    next;
                }

                Config::Metrics::update_config_if_changed($config);
                send_data($client, $start, $end);
                next;
            }

            if ($q eq 'config') {
                $client->send_file_response($config->{general}->{config_path});
                next;
            }
            
            $client->send_error(400, "Invalid q= value");
            next;
        }
        
        $client->send_error(RC_FORBIDDEN);
    }

    $client->close();
    undef $client;
}


__DATA__

=head1 NAME

http-server-metrics - HTTP server that provides read access to metrics database

=head1 SYNOPSIS

http-server-metrics --config=<config file> --listen=<IP:port>

=head1 OPTIONS

=over 8

=item B<--config=<...>>

Path to configuration ini file

=item B<--listen=<IP:port>> or B<-l IP:PORT>

IP and port on which to listen.

=item B<--help>

Print a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 COPIRIGHT

Evgenii Lepikhin <johnlepikhin@gmail.com>

=cut
