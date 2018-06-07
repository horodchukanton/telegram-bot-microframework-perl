#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use utf8;

$| = 1;

our $Bin;
BEGIN {
    use FindBin '$Bin';
}
use lib $Bin . '/../lib';

use AnyEvent;
use Plugin::Telegram;
use Encode;

our %config;
require './bin/config.pl';

print "Hello, world!\n";

my $quit_var = AnyEvent->condvar();

my $bot = Plugin::Telegram->new(%config);
$bot->start();

my %restaurants = (
    'vilki-palki.od.ua' => 1,
    'pizza.od.ua'       => 1,
    'alpina.od.ua'      => 1,
    'wok.od.ua'         => 1,
    'didrih.com'        => sub {
        my ( $sec, $min, $hour ) = localtime();
        if ($hour >= 12){
            return {
                message => "Skipping didrih.com, because it's to late ($hour:$min)"
            };
        };
        return 1;
    }
);
srand;

$bot->remove_callback('default');

sub propose {
    my ( $message, $chat_id ) = @_;
    my $number = int(rand() * scalar(keys %restaurants));

    my $name = @{[ keys(%restaurants) ]}[$number];

    my $proposed = $restaurants{$name};

    # Allow checks for given variant
    if (ref $proposed && ref $proposed eq 'CODE') {
        my $check = $proposed->();

        if (!$check){
            return propose(@_);
        }
        elsif (ref $check eq 'HASH' && $check->{message}){
            $bot->send_response($check->{message}, $chat_id);
            return propose(@_);
        }
    }

    $bot->send_response($name, $chat_id);
}

$bot->add_callback('/food_selector', \&propose);
$bot->add_callback('@foodSelectorBot /food_selector', \&propose);

$quit_var->recv();

1;