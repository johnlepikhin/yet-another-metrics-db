package BinaryReader;

require 5.008001;
use warnings;
use strict;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();

my $buflen = 8192;

sub new {
    my $class = shift;
    my $self = [shift, '', 0, 0];

#        _fh => shift,
#        _buffer => '',
#        _position => 0,
#        _length => 0
#    };

    bless $self, $class;

    return $self;
}

sub _fillBuffer ($) {
    my $self = shift;

    my $rd = read($self->[0], $self->[1], $buflen);
    $self->[2] = 0;
    $self->[3] = $rd;
}

sub _getLeftBytes ($) {
    my $self = shift;

    return ($self->[3] - $self->[2]);
}

sub getByte ($) {
    if ($_[0]->[2] >= $_[0]->[3]) {
        _fillBuffer $_[0];
    }

    if ($_[0]->[2] >= $_[0]->[3]) {
        return;
    }

    return substr $_[0]->[1], $_[0]->[2]++, 1;
}

# TODO
sub getBytes ($$) {
    my $self = shift;
    my $length = shift;

    if ($self->[2] + $length < $self->[3]) {
        $self->[2]+=$length;
        return substr $self->[1], $self->[2]-$length, $length;
    }
    
    my $r = '';
    for (1..$length) {
        my $b = $self->getByte();
        if (length ($b)) {
            $r .= $b;
        } else {
            die "cannot read requested amount of bytes";
        }
    }

    return $r;
}

sub seekForward($$) {
    my $self = shift;
    my $offset = shift;

    if ($offset < 0) {
        die "Cannot seek back";
    }

    if (!$offset) {
        return;
    }

    my $newPos = $offset + $self->[2];

    while (1) {
        if ($newPos < $self->[3]) {
            $self->[2] = $newPos;
            return;
        }

        $newPos -= $self->[3];

        _fillBuffer ($self);

        if (!_getLeftBytes($self)) {
            die "cannot seek beyond end of file";
        }
    };
}

1;
