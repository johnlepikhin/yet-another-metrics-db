package Storage;

require 5.008001;
use warnings;
use strict;

use File::Path;
use Encode::Variable;
use Exporter;
use Time::HiRes;
use BinaryReader;

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

sub read_uint($) {
    my $r = BinaryReader::getByte $_[0];

    $r = ord $r;

    return $r if $r < 249;

    my $ret = 0;
    my $bytes = $r-249+2;
    for my $byte (1..$bytes) {
        $ret = ($ret << 8) | ord $_[0]->getByte();
    }

    return $ret;
}

sub read_int($) {
    my $r = read_uint($_[0]);
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

    my $reader = BinaryReader->new($fh);

    sub reader_of_datatype($) {
        if ($_[0] eq 'uint') {
            return \&read_uint;
        } elsif ($_[0] eq 'int') {
            return \&read_int;
        } else {
            warn "cannot read datatype: $_[0]\n";
            return undef;
        }
    }
    
    my @keys = map { /^metrics:(.*)/; [$_, $1, $config->{$_}->{values}->{datatype}, reader_of_datatype($config->{$_}->{values}->{datatype})]; }
    sort { $config->{$a}->{id_in_group} <=> $config->{$b}->{id_in_group} }
    grep { /^metrics:/ && $config->{$_}->{group_id} == $file->{group_id} }
    keys %$config;
    
    while ($_ = $reader->getByte()) {
        goto release_fh_return if $_ ne 'M';

        eval {
            my $record_version = read_uint($reader);
            my $tick_offset = read_uint($reader);
            my $group_mask = read_uint($reader);
            my $values_length = read_uint($reader);

            my $tick = $file->{floor_tick} + $tick_offset;
            my $timestamp = $tick*$config->{general}->{values}->{tick_size_ms};
            
            if (!$header_filter_fn->($record_version, $tick_offset, $group_mask, $values_length, $timestamp, $tick)) {
                $reader->seekForward($values_length);
                return; # eval
            }

            goto release_fh_return if $record_version > $version;
            goto release_fh_return if $tick > $end_tick;

            for (0..$#keys) {
                my $bit = $config->{$keys[$_]->[0]}->{id_in_group};
                next if !($group_mask & (1 << $bit));

                if (defined $keys[$_]->[3]) {
                    $ret->{$timestamp}->{$keys[$_]->[1]} = $keys[$_]->[3]->($reader);
                }
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
        if ($_[5] < $start_tick || $_[5] > $end_tick) {
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
