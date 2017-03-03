
package Config::IniPlain;

require 5.008001;
use warnings;
use strict;
use Exporter;
use POSIX;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();

my $metrics_per_group = 64;

BEGIN {
    $Config::IniPlain::errstr  = '';
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

sub errstr { $Config::IniPlain::errstr }
sub _error { $Config::IniPlain::errstr = $_[1]; undef }

1;

