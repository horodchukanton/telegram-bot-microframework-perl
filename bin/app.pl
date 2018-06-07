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
require "$Bin/config.pl";
srand;

my $bot = Plugin::Telegram->new(%config);
$bot->start();

my %restaurants = (
    'https://vilki-palki.od.ua/' => 1,
    'https://pizza.od.ua/'       => 1,
    'http://alpina.od.ua/'       => 1,
    'https://wok.od.ua/'         => 1,
    'https://didrih.com/'        => sub {
        my ( $sec, $min, $hour ) = localtime();
        if ($hour >= 12) {
            return {
                message => "Skipping didrih.com, because it's too late ($hour:$min)"
            };
        };
        return 1;
    }
);

my %friday_restaurants = (
    'chacha' => 'https://gorilla.com.ua/odessa/restaurants/Chacha/menu',
    'givi'   => 'https://gorilla.com.ua/odessa/restaurants/givitome/menu',
);

# Disable "Can't understand you" callback
$bot->remove_callback('default');

sub propose {
    my ( $message, $chat_id ) = @_;

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
        localtime(time);

    $wday = 5;

    # Friday has special menu
    my $today_menu = ( $wday == 5 ) ? \%friday_restaurants : \%restaurants;

    # Choose random one
    my $number = int(rand() * scalar(keys %{$today_menu}));
    my $name = @{[ keys(%{$today_menu}) ]}[$number];

    my $proposed = $today_menu->{$name};

    # Tell $proposed to check himself if it can
    if (ref $proposed && ref $proposed eq 'CODE') {
        my $check = $proposed->();

        if (! $check) {
            return propose(@_);
        }
        elsif (ref $check eq 'HASH' && $check->{message}) {
            $bot->send_response($check->{message}, $chat_id);
            return propose(@_);
        }
    }
    elsif (! ( ref $proposed ) && $proposed ne '1') {
        $name = $proposed;
    }

    # Tell the verdict
    $bot->send_response($name, $chat_id);
}

$bot->add_callback('/food_selector', \&propose);

$bot->add_callback('~какой.*день\??', sub {
    my ( $message, $chat_id ) = @_;

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
        localtime(time);

    my $friday_text = qq/Вай-вай-вай, какой хороший день сегодня, дорогой!

Мой гора любимый - родина Кавказ!
Там в горах высоких я барашков пас.
Чтобы не потели, заводил их в тень,
Чтобы не скучали, танцевал весь день.

Аравай-вай! Вай-вай-вай-вай, аравай-вай! Вай-вай-вай-вай/;

    my $response_text = ( $wday == 5 ) ? $friday_text : 'Нормальный, блядь, день. Отъебись';
    $bot->send_response($response_text, $chat_id);
});


# Should be added as the inline query callback
#$bot->add_callback('@foodSelectorBot /food_selector', \&propose);

# Start event loop
AnyEvent->condvar()->recv();

1;