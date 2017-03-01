#!/usr/bin/perl

use Time::HiRes qw(setitimer ITIMER_REAL);

use warnings;
use strict;

require 5.008001;

my $metrics_per_group = 64;

my $version = 0;

package Config::Tiny;

BEGIN {
    $Config::Tiny::errstr  = '';
}

sub new { bless {}, shift }

sub read {
    my $class = ref $_[0] ? ref shift : shift;
    my $file  = shift or return $class->_error('No file name provided');

    my $encoding = shift;
    $encoding    = $encoding ? "<:$encoding" : '<';
    local $/     = undef;

    open( CFG, $encoding, $file ) or return $class->_error( "Failed to open file '$file' for reading: $!" );
    my $contents = <CFG>;
    close( CFG );

    return $class -> _error("Reading from '$file' returned undef") if (! defined $contents);

    return $class->read_string( $contents );
}

sub read_string {
    my $class = ref $_[0] ? ref shift : shift;
    my $self  = bless {}, $class;
    return undef unless defined $_[0];

    my $ns      = '_';
    my $section_id = 0;
    my $counter = 0;
    foreach ( split /(?:\015{1,2}\012|\015|\012)/, shift ) {
        $counter++;

        next if /^\s*(?:\#|\;|$)/;

        s/\s\;\s.+$//g;

        if ( /^\s*\[\s*(.+?)\s*\]\s*$/ ) {
            if (exists $self->{$1}) {
                return $self->_error( "Section '$1' already defined, second definition at line $counter: '$_'" );
            }

            my $id = $section_id++;
            my $group_id = POSIX::floor($id/$metrics_per_group);
            my $id_in_group = $id-$group_id*$metrics_per_group;
            $self->{$ns = $1} = {
                id => $id,
                group_id => $group_id,
                id_in_group => $id_in_group,
                values => {}
            };
            next;
        }

        if ( /^\s*([^=]+?)\s*=\s*(.*?)\s*$/ ) {
            if (exists $self->{$ns}->{values}->{$1}) {
                return $self->_error( "Value '$1' in section '$ns' already defined, second definition at line $counter: '$_'" );
            }
            $self->{$ns}->{values}->{$1} = $2;
            next;
        }
        return $self->_error( "Syntax error at line $counter: '$_'" );
    }
    $self;
}

sub errstr { $Config::Tiny::errstr }
sub _error { $Config::Tiny::errstr = $_[1]; undef }






package Config::Metrics;

sub max($$) {
    my $x = shift;
    my $y = shift;

    ($x, $y)[$x < $y];
}

sub check ($) {
    my $config = shift;


    $config->{general}->{values}->{tick_size_ms} ||= 60000;
    $config->{general}->{values}->{listen} ||= '/tmp/perl-collect.sock';
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
        }
    }
    return $config;
}






package Encode::Variable::Int;

sub uint8 ($) {
    my $v = shift;

    if ($v >= 2**56) {
        return sprintf "%c%c%c%c%c%c%c%c%c", 255
            , ($v >> 56), (($v >> 48) & 0xff), (($v >> 40) & 0xff), (($v >> 32) & 0xff), (($v >> 24) & 0xff), (($v >> 16) & 0xff), (($v >> 8) & 0xff), ($v & 0xff);
    } elsif ($v >= 2**48) {
        return sprintf "%c%c%c%c%c%c%c%c", 254
            , ($v >> 48), (($v >> 40) & 0xff), (($v >> 32) & 0xff), (($v >> 24) & 0xff), (($v >> 16) & 0xff), (($v >> 8) & 0xff), ($v & 0xff);
    } elsif ($v >= 2**40) {
        return sprintf "%c%c%c%c%c%c%c"
            , 253, ($v >> 40), (($v >> 32) & 0xff), (($v >> 24) & 0xff), (($v >> 16) & 0xff), (($v >> 8) & 0xff), ($v & 0xff);
    } elsif ($v >= 2**32) {
        return sprintf "%c%c%c%c%c%c"
            , 252, ($v >> 32), (($v >> 24) & 0xff), (($v >> 16) & 0xff), (($v >> 8) & 0xff), ($v & 0xff);
    } elsif ($v >= 2**24) {
        return sprintf "%c%c%c%c%c"
            , 251, ($v >> 24), (($v >> 16) & 0xff), (($v >> 8) & 0xff), ($v & 0xff);
    } elsif ($v >= 2**16) {
        return sprintf "%c%c%c%c"
            , 250, ($v >> 16), (($v >> 8) & 0xff), ($v & 0xff);
    } elsif ($v >= 249) {
        return sprintf "%c%c%c"
            , 249, ($v >> 8), ($v & 0xff);
    } else {
        return sprintf "%c", $v;
    }
}

sub int8 ($) {
    my $v = shift;

    die "signed int8 overflow" if $v >= 2**63;

    my $sign = ($v < 0) ? 1 : 0;
    my $abs = abs $v;

    $abs = $sign + ($abs << 1);

    return (uint8 $abs);
}

sub encode ($$) {
    my $type = shift;
    my $value = shift;

    if ($type eq 'uint') {
        return uint8($value);
    } elsif ($type eq 'int') {
        return int8($value);
    }
}





package Storage;

use File::Path;

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
    
    my $tick_size_ms = $config->{general}->{values}->{tick_size_ms};

    my $path = $directories . '/' . ($floor_tick*$tick_size_ms) . '-' . $group_id;

    File::Path::make_path($directories);

    open (my $fh, '>>:raw', $path) || die "Cannot open file '$path' for append: $?";

    my $tick_offset = $tick-$floor_tick;
    my $group_mask = get_group_bitmask($group_values);

    my $record = 'M'
        . (Encode::Variable::Int::uint8 $version)
        . (Encode::Variable::Int::uint8 $tick_offset)
        . (Encode::Variable::Int::uint8 $group_mask);

    foreach (sort {$group_values->{$a}->{id_in_group} <=> $group_values->{$b}->{id_in_group}} keys %$group_values) {
        $record .= Encode::Variable::Int::encode ($group_values->{$_}->{datatype}, $group_values->{$_}->{value});
    }

    print $fh $record;
    
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
        print "process group $group_id\n";

        my %group_values;
        
        foreach (grep { /^metrics:/ && $config->{$_}->{group_id} == $group_id } keys %$config) {
            my ($metrics_name) = $_ =~ /^metrics:(.*)/;

            if (exists $current->{$metrics_name}) {
                $group_values{$metrics_name}{value} = $current->{$metrics_name};
                $group_values{$metrics_name}{datatype} = $config->{$_}->{values}->{datatype};
                $group_values{$metrics_name}{id_in_group} = $config->{$_}->{id_in_group};
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

sub read_file($$$$$) {
    my $config = shift;
    my $file = shift;
    my $ret = shift;
    my $start_tick = shift;
    my $end_tick = shift;

    print "$file->{path}\n";
    
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

            my $tick = $file->{floor_tick} + $tick_offset;

            goto release_fh_return if $record_version > $version;
            goto release_fh_return if $tick > $end_tick;

            my $tick_size_ms = $config->{general}->{values}->{tick_size_ms};
            my $timestamp = $tick*$tick_size_ms;
            
#            print "version=$version, tick_offset=$tick_offset, group_mask=$group_mask\n";

            foreach my $key (sort { $config->{$a}->{id_in_group} <=> $config->{$b}->{id_in_group} }
                     grep { /^metrics:/ && $config->{$_}->{group_id} == $file->{group_id} }
                     keys %$config)
            {
                my $bit = $config->{$key}->{id_in_group};
                next if !($group_mask & (1 << $bit));

                my ($metrics) = $key =~ /^metrics:(.*)/;

                my $datatype = $config->{$key}->{values}->{datatype};

                next if $tick < $start_tick;

                if ($datatype eq 'uint') {
                    my $v = read_uint($fh);
                    $ret->{$timestamp}->{$metrics} = $v;
                } else {
                    die "cannot read datatype: $datatype\n";
                }
            }
        };
        goto release_fh_return if $@ && print "??? $@\n";
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

    my %r;
    foreach (@$files) {
        read_file ($config, $_, \%r, $start_tick, $end_tick);
    }

    return \%r;
}







package main;

use POSIX qw(mkfifo);
use Data::Dumper;

sub open_fifo ($) {
    my $config = shift;

    my $fifo = $config->{general}->{values}->{listen};

    if (!-e $fifo) {
        mkfifo ($fifo, 0600) || die "mkfifo($fifo) failed: $!";
    }

    if (!-p $fifo) {
        die "$fifo is not a FIFO file";
    }

    my $fh;
    while (1) {
        open ($fh, '<:utf8', $fifo) && return $fh;
        die "cannot open $fifo: $?" if (!$!{EINTR});
    };
}

sub process_fifo($$$) {
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
                $current->{$key} = $value;
            }
        } elsif (/^exit$/i) {
            exit 0;
        }
    }

  release_fh_return:
    close $fh;
}

sub loop_fifo($) {
    my $config = shift;

    my %current;

    $SIG{ALRM} = sub {
        Storage::save_current($config, \%current);
        %current = ();
    };

    my $tick_size = $config->{general}->{values}->{tick_size_ms}/1000;
    setitimer(ITIMER_REAL, $tick_size, $tick_size);
    
    while (1) {
        my $fh = open_fifo($config);
        process_fifo($config, $fh, \%current);
    }
}

my $config = Config::Tiny->read('datainfo.ini') || die Config::Tiny::errstr();
Config::Metrics::check($config) || die Config::Tiny::errstr();

#loop_fifo($config);

# sample reading
my $period = Storage::read_period($config, 1487853670-100000, 1487853980+10000000);
#print Dumper($period);
