package Config::Metrics;

require 5.008001;
use warnings;
use strict;
use Exporter;
use Config::IniPlain;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();

sub max($$) {
    my $x = shift;
    my $y = shift;

    ($x, $y)[$x < $y];
}

sub check ($) {
    my $config = shift;

    $config->{general}->{values}->{tick_size_ms} ||= 60000;
    $config->{general}->{values}->{listen} || return $config->_error("Missing required parameter 'listen' in section [general]");
    $config->{general}->{values}->{tree_root} || return $config->_error("Missing required parameter 'tree_root' in section [general]");
    $config->{general}->{values}->{tree_configuration} ||= '256 256 1440';

    $config->{general}->{max_group_id} = -1;

    my ($entries_per_file, @entries_per_dir_) = reverse (split /\s+/, $config->{general}->{values}->{tree_configuration});
    $config->{general}->{entries_per_file} = $entries_per_file;
    my @entries_per_dir = ();
    my $e = $entries_per_file;
    foreach (@entries_per_dir_) {
        $e *= $_;
        push @entries_per_dir, $e;
    }
    @entries_per_dir = reverse @entries_per_dir;
    $config->{general}->{entries_per_dir} = \@entries_per_dir;

    foreach my $section (sort {$config->{$a}->{id} <=> $config->{$b}->{id}} keys %$config) {
        if ($section =~ /^metrics:(.*)/) {
            if ($1 eq '') {
                return $config->_error("Empty metrics name in section [metrics:]");
            }

            $config->{general}->{max_group_id} = max($config->{general}->{max_group_id}, $config->{$section}->{group_id});

            if (!exists $config->{$section}->{values}->{datatype}) {
                return $config->_error("'datatype' is not defined in section [metrics:$section]");
            } else {
                my $type = $config->{$section}->{values}->{datatype};
                if ($type !~ /^(uint|int)$/) {
                return $config->_error("Undefined data type '$type' in section [metrics:$section]");
                }
            }

            if (exists $config->{$section}->{values}->{agregate_fn}) {
                my $type = $config->{$section}->{values}->{agregate_fn};
                if ($type !~ /^(take-last|numeric-diff)$/) {
                    return $config->_error("Unknown agregate_fn type '$type' in section [metrics:$section]");
                }
            } else {
                $config->{$section}->{values}->{agregate_fn} = 'take-last';
            }

            if (exists $config->{$section}->{values}->{output_value_filter}) {
                my $filter = $config->{$section}->{values}->{output_value_filter};

                if ($filter ne 'skip-zero') {
                    return $config->_error("Unknown output_value_filter type '$filter' in section [metrics:$section]");
                }
            }

        }
    }
    return $config;
}

sub read ($) {
    my $file = shift;
    
    my $config = Config::IniPlain->read($file) || die Config::IniPlain::errstr();
    check($config) || die Config::IniPlain::errstr();

    $config->{general}->{config_path} = $file;

    my @stat = stat $file;
    
    $config->{general}->{config_size} = $stat[7];
    $config->{general}->{config_mtime} = $stat[9];

    return $config;
}

sub add_metrics($$$$) {
    my $config = shift;
    my $name = shift;
    my $datatype = shift;
    my $values = shift;

    my @keys = keys %$config;
    
    return if exists $config->{"metrics:$name"};

    open my $fh, '>>', $config->{general}->{config_path} || die "Cannot open '$config->{general}->{config_path}': $?";

    my $pairs = "datatype = $datatype\n";
    if (defined $values) {
        foreach (sort keys %$values) {
            $pairs .= "$_ = $values->{$_}\n";
        }
    }
    
    print $fh "\n[metrics:$name]\n\n$pairs\n";
    close $fh;
}

1;
