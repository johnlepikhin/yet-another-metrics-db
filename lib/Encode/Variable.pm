
package Encode::Variable;

require 5.008001;
use warnings;
use strict;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();

sub uint8 ($) {
    my $v = shift;

    die "uint8 < 0" if $v < 0;

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

1;
