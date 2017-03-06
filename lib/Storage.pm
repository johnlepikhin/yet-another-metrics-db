package Storage;

require 5.008001;
use warnings;
use strict;

use File::Path;
use Encode::Variable;
use Exporter;
use Time::HiRes;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();

my $version = 0;

sub get_dirs_path_of_tick($$) {
    my $config = shift;
    my $tick = shift;

    my $path = $config->{general}->{values}->{tree_root};
    $path .= '/' . (POSIX::floor($tick/$_)*$_*$config->{general}->{values}->{tick_size_ms}) foreach @{$config->{general}->{entries_per_dir}};

    return $path;
}

sub get_floor_first_filetick_of_tick($$) {
    my $config = shift;
    my $tick = shift;

    my $div = $config->{general}->{entries_per_file};

    return (POSIX::floor($tick/$div)*$div);
}

sub get_group_bitmask($) {
    my $group_values = shift;

    my $mask = 0;

    $mask |= 1 << $group_values->{$_}->{id_in_group} foreach keys %$group_values;

    return $mask;
}

sub save_group($$$$$$) {
    my $config = shift;
    my $group_id = shift;
    my $group_values = shift;
    my $directories = shift;
    my $tick = shift;
    my $floor_tick = shift;

    return if !keys %$group_values;
    
    my $tick_size_ms = $config->{general}->{values}->{tick_size_ms};

    my $path = $directories . '/' . ($floor_tick*$tick_size_ms) . '-' . $group_id;

    File::Path::make_path($directories);

    open (my $fh, '>>:raw', $path) || die "Cannot open file '$path' for append: $?";

    my $tick_offset = $tick-$floor_tick;
    my $group_mask = get_group_bitmask($group_values);

    my $header = 'M'
        . (Encode::Variable::uint8 $version)
        . (Encode::Variable::uint8 $tick_offset)
        . (Encode::Variable::uint8 $group_mask);

    my $values = '';

    foreach my $metrica (sort {$group_values->{$a}->{id_in_group} <=> $group_values->{$b}->{id_in_group}} keys %$group_values) {
        my $v = Encode::Variable::encode ($group_values->{$metrica}->{datatype}, $group_values->{$metrica}->{value});
        $values .= $v;
    }

    my $length = Encode::Variable::uint8 (length $values);

    print $fh "$header$length$values";
    
    close ($fh);
}

sub save_current($$) {
    my $config = shift;
    my $current = shift;

    my $tick_size_ms = $config->{general}->{values}->{tick_size_ms};

    my $tick = POSIX::floor (1000*Time::HiRes::time/$tick_size_ms);

    my $dirs = get_dirs_path_of_tick($config, $tick);
    my $floor_tick = get_floor_first_filetick_of_tick($config, $tick);

    for my $group_id (0..$config->{general}->{max_group_id}) {
        print "save group $group_id\n";

        my %group_values;
        
        foreach my $section (grep { /^metrics:/ && $config->{$_}->{group_id} == $group_id } keys %$config) {
            my ($metrics_name) = $section =~ /^metrics:(.*)/;

            my $add = sub ($) {
                my $value = shift;

                if (exists $config->{$section}->{values}->{output_value_filter}) {
                    my $filter = $config->{$section}->{values}->{output_value_filter};

                    if ($filter eq 'skip-zero') {
                        return if $value == 0;
                    }
                }

                $group_values{$metrics_name}{value} = $value;
                $group_values{$metrics_name}{datatype} = $config->{$section}->{values}->{datatype};
                $group_values{$metrics_name}{id_in_group} = $config->{$section}->{id_in_group};
            };
            
            if (exists $current->{$metrics_name}) {
                my $agregate_fn = $config->{$section}->{values}->{agregate_fn};
                
                if ($agregate_fn eq 'take-last') {
                    $add->($current->{$metrics_name});

                } elsif ($agregate_fn eq 'numeric-diff') {
                    if (exists $current->{$metrics_name}->{prev} && exists $current->{$metrics_name}->{current}) {
                        my $value = $current->{$metrics_name}->{current} - $current->{$metrics_name}->{prev};
                        $add->($value);
                    }
                    if (exists $current->{$metrics_name}->{current}) {
                        $current->{$metrics_name}->{prev} = $current->{$metrics_name}->{current};
                    }
                    delete $current->{$metrics_name}->{current};
                }
                
            }
        }

        if (keys %group_values) {
            save_group ($config, $group_id, \%group_values, $dirs, $tick, $floor_tick);
        }
    }
}

sub get_files_list($$$) {
    my $config = shift;
    my $start_tick = shift;
    my $end_tick = shift;

    my $tick_size_ms = $config->{general}->{values}->{tick_size_ms};

    my @files;
    for (my $checkpoint=$start_tick; $checkpoint<=$end_tick; $checkpoint+=$config->{general}->{entries_per_file}) {
        my $dirs = get_dirs_path_of_tick($config, $checkpoint);
        my $floor_tick = get_floor_first_filetick_of_tick($config, $checkpoint);

        for my $group_id (0..$config->{general}->{max_group_id}) {
            my $path = $dirs . '/' . ($floor_tick*$tick_size_ms) . '-' . $group_id;
            if (-e $path) {
                push @files, {path => $path, floor_tick => $floor_tick, group_id => $group_id }
            } else {
                $path .= '.gz';
                if (-e $path) {
                    push @files, {path => $path, floor_tick => $floor_tick, group_id => $group_id }
                }
            }
        }

    }

    return \@files;
}

sub read_bytes($$) {
    my $fh = shift;
    my $len = shift;

    my $r = '';
    my $total_rd = 0;
    while ($total_rd < $len) {
        my $rd = read($fh, $r, $len-$total_rd, $total_rd);
        die if !defined $rd;
        $total_rd += $rd;
    }

    $r;
}

sub read_uint($) {
    my $fh = shift;

    my $r = read_bytes($fh, 1);

    $r = unpack 'C', $r;

    return $r if $r < 249;

    $r = read_bytes($fh, $r-249+2);
    my $ret = 0;
    for my $pos (0..length ($r)-1) {
        my $byte = unpack 'C', substr($r, $pos, 1);
        $ret |= $byte << 8*(length($r) - $pos - 1);
    }

    return $ret;
}

sub read_int($) {
    my $fh = shift;

    my $r = read_uint($fh);
    my $v = $r >> 1;
    $v = -$v if ($r & 1);

    return $v;
}

sub read_file($$$$$$) {
    my $config = shift;
    my $file = shift;
    my $ret = shift;
    my $start_tick = shift;
    my $end_tick = shift;
    my $header_filter_fn = shift;

    my $fh;
    if ($file->{path} =~ /.gz$/) {
        open ($fh, '-|:raw', "zcat '$file->{path}'") || return;
    } else {
        open ($fh, '<:raw', $file->{path}) || return;
    }
    
    local $/ = \1;

    while (<$fh>) {
        goto release_fh_return if $_ ne 'M';
        eval {
            my $record_version = read_uint($fh);
            my $tick_offset = read_uint($fh);
            my $group_mask = read_uint($fh);
            my $values_length = read_uint($fh);

            my $tick = $file->{floor_tick} + $tick_offset;
            my $tick_size_ms = $config->{general}->{values}->{tick_size_ms};
            my $timestamp = $tick*$tick_size_ms;
            
            if (!$header_filter_fn->($record_version, $tick_offset, $group_mask, $values_length, $timestamp, $tick)) {
                seek($fh, $values_length, 1);
                return;
            }

            goto release_fh_return if $record_version > $version;
            goto release_fh_return if $tick > $end_tick;

            foreach my $key (sort { $config->{$a}->{id_in_group} <=> $config->{$b}->{id_in_group} }
                     grep { /^metrics:/ && $config->{$_}->{group_id} == $file->{group_id} }
                     keys %$config)
            {
                my $bit = $config->{$key}->{id_in_group};
                next if !($group_mask & (1 << $bit));

                my ($metrics) = $key =~ /^metrics:(.*)/;

                my $datatype = $config->{$key}->{values}->{datatype};

                next if $tick < $start_tick;

                my $v;
                if ($datatype eq 'uint') {
                    $v = read_uint($fh);
                } elsif ($datatype eq 'int') {
                    $v = read_int($fh);
                } else {
                    warn "cannot read datatype: $datatype\n";
                }
                $ret->{$timestamp}->{$metrics} = $v if defined $v;
            }
        };
        goto release_fh_return if $@;
    }

    
  release_fh_return:
    close $fh;
}

sub read_period($$$) {
    my $config = shift;
    my $start_date = shift;
    my $end_date = shift;

    my $tick_size_ms = $config->{general}->{values}->{tick_size_ms};
    my $start_tick = POSIX::floor (1000*$start_date/$tick_size_ms);
    my $end_tick = POSIX::floor (1000*$end_date/$tick_size_ms);

    my $files = get_files_list($config, $start_tick, $end_tick);

    my $filter = sub ($$$$$$) {
        my $record_version = shift;
        my $tick_offset = shift;
        my $group_mask = shift;
        my $values_length = shift;
        my $timestamp = shift;
        my $tick = shift;

        if ($tick < $start_tick || $tick > $end_tick) {
            return 0;
        } else {
            return 1;
        }
    };
    
    my %r;
    foreach (@$files) {
        read_file ($config, $_, \%r, $start_tick, $end_tick, $filter);
    }

    return \%r;
}

1;
