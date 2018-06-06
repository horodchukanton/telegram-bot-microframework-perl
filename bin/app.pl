#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

our $Bin;
BEGIN {
    use FindBin '$Bin';
}
use lib $Bin . '/../lib';
use Plugin::Telegram;

our %config;
require './bin/config.pl';

print "Hello, world!\n";

my $bot = Plugin::Telegram->new(%config);
$bot->start();

1;