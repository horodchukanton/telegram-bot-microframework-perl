package Plugin::Telegram;
use strict;
use warnings FATAL => 'all';

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;

use Data::Dumper;

use Plugin::Telegram::BotAPI;
use Plugin::Telegram::Operation;
#use Plugin::Telegram::ModuleInterface;

my $debug = 5;
my $Bot_API;

my %user_for_chat_id = ();
my %admin_for_chat_id = ();

# Operation will get all messages for client while in 'locked' mode
my %operation_lock_on_chat_id = ();


#**********************************************************
=head2 new()

=cut
#**********************************************************
sub new {
    my ( $class, %config ) = @_;

    my $self;
    $self = {
        conf           => \%config,
        debug          => $config{debug} || 1,
        token          => $self->{conf}->{TELEGRAM_TOKEN},
        last_update_id => 0,
        cb             => {
            'default'  => sub {
                $self->action_unknown_command(@_);
            },
            '/balance' => sub {
                my $message = shift;
                $self->send_response("Sorry, but I can't do it now", $message->{chat}->{id});
            },
            '/hello'   => sub {
                my $message = shift;
                $self->action_greetings($message->{chat}->{id});
            }
        }
    };

    bless($self, $class);
    return $self;
}

#**********************************************************
=head2 start() - begins Telegram API work

  Returns:
    1
    
=cut
#**********************************************************
sub start {
    my ( $self ) = @_;

    $self->{debug} = $self->{conf}->{TELEGRAM_API_DEBUG} || $debug;

    $Bot_API = Plugin::Telegram::BotAPI->new({
        token => $self->{conf}{token}
    });

    # TODO: allow to set custom object for authorization
#    $self->load_clients();

    $self->set_timer($self->{conf}->{interval});

    return;
}

#**********************************************************
=head2 set_timer()

=cut
#**********************************************************
sub set_timer {
    my ( $self, $interval ) = @_;

    $self->{timer} = AnyEvent->timer(
        after    => 0,
        interval => $interval,
        cb       => sub {
            print qq/"LOG_ERROR", "[ Telegram ]", "Request"/;

            eval {
                $Bot_API->getUpdates(
                    {
                        offset  => $self->{last_update_id} + 1,
                        timeout => 4
                    },
                    sub {
                        my $updates = shift;
                        if ($updates->{ok} && scalar(@{$updates->{result}})) {
                            $self->process_updates(@{$updates->{result}});
                        }
                    }
                );

            };
            if ($@) {
                print qq/"LOG_ERROR", "[ Telegram ]", $@/;
            }
        });

}

#**********************************************************
=head2 add_callback($message, $cb)

=cut
#**********************************************************
sub add_callback {
    my ( $self, $message, $cb ) = @_;
    $self->{cb}->{$message} = $cb;
    return 1;
}

#**********************************************************
=head2 remove_callback()

=cut
#**********************************************************
sub remove_callback {
    my ( $self, $name ) = @_;
    delete $self->{cb}->{$name};
    return 1;
}

#**********************************************************
=head2 process_updates()

=cut
#**********************************************************
sub process_updates {
    my ( $self, @updates ) = @_;

    # Show message
    foreach my $update (@updates) {
        next if ($self->{last_update_id} && $update->{update_id} <= $self->{last_update_id});

        $self->{last_update_id} = $update->{update_id};

        my $message = $update->{message};
        print Dumper($update) if ($self->{conf}->{debug} > 4);
        print Dumper($message) if ($self->{conf}->{debug} > 3);

        #    if ( $message->{contact} ) {
        #      print "Got phone: $message->{contact} $message->{contact}->{phone_number} \n";
        #      next;
        #    }

        if (exists $update->{callback_query}
            && $update->{callback_query}->{from}
            && $update->{callback_query}->{from}->{id}
        ) {
            my $chat_id = $update->{callback_query}->{from}->{id};

            my $authorized = $self->is_authenticated($chat_id);
            return 0 unless ($authorized);

            return $self->process_callback_query(
                $update->{callback_query},
                {
                    CHAT_ID     => $chat_id,
                    CLIENT_TYPE => ( $authorized < 0 ) ? 'UID' : 'AID',
                    CLIENT_ID   => ( $authorized < 0 ) ? $user_for_chat_id{$chat_id} : $admin_for_chat_id{$chat_id}
                }
            );
        }

        next if (! $message->{text});
        my $chat_id = $message->{chat}->{id};

        # Check for start command
        if ($message->{text} =~ /^\/start/) {
            if ($message->{text} =~ /\/start ([ua])_([a-zA-Z0-9]+)/) {
                my $type = $1;
                my $sid = $2;

                print qq/"LOG_NOTICE", " Telegram ", "Auth  for $type $sid"/;

                if ($self->authenticate($type, $sid, $chat_id)) {
                    print qq/"LOG_DEBUG", " Telegram ", "Authorized $type $sid"/;
                    $self->send_response("You've been registered", $chat_id);
                    next;
                }
            }

            print qq/"LOG_INFO", " Telegram ", "Auth failed  for $message->{from}->{username} ($chat_id)"/;
            $self->send_response("Sorry, can't authorize you. Please log in to web interface and try again", $chat_id);
            return 0;
        }

        my $authorized = $self->is_authenticated($chat_id);
        # Check if we have such a client
        if (! $authorized) {
            $self->send_response("Unauthorized", $chat_id);
        }
        else {

            #      my $client_type = ($authorized < 0) ? 'UID' : 'AID',;
            #      my $client_id = ($authorized < 0) ? $client_for_chat_id{$chat_id} : $admin_for_chat_id{$chat_id};

            if (exists $operation_lock_on_chat_id{$chat_id}) {
                my Plugin::Telegram::Operation $operation = $operation_lock_on_chat_id{$chat_id};

                my $should_finish = (
                    ( $message->{text} && $message->{text} eq '/cancel' )
                        || $operation->on_message($message)
                );
                if ($should_finish) {
                    $operation->on_finish();
                    delete $operation_lock_on_chat_id{$chat_id};
                }

                return 1;
            }

            if (defined $self->{cb}->{$message->{text}}) {
                $self->{cb}->{$message->{text}}->($message);
            }
            else {
                $self->{cb}->{default}->($message);
            }

        }
    };

    return $self->{last_update_id};
}

#**********************************************************
=head2 process_callback_query($query) - processes update got from message button

  Arguments:
    $query -
    
  Returns:
  
  
=cut
#**********************************************************
sub process_callback_query {
    my ( $self, $query, $attr ) = @_;

    return 0 unless ($attr->{CHAT_ID});

    # TODO: Check if already in operation

    my $data_raw = $query->{data};
    return 0 unless ($data_raw);

    my ( @data ) = split(':', $data_raw);
    my $module = shift @data;

    return 0 unless ($module);

    my Plugin::Telegram::Operation $operation = 0;

    if (uc $module eq 'MSGS') {
        $operation = Plugin::Telegram::ModuleInterface::process_data($self, \@data, $attr);
    }
    return 0 unless ($operation);

    # Set lock ( all messages will go to operation )
    $operation_lock_on_chat_id{$attr->{CHAT_ID}} = $operation;

    $operation->start();

    return 1;
}


#**********************************************************
=head2 is_authenticated($chat_id) - checks if is authorized

  Arguments:
    $chat_id - chat_id to check
    
  Returns:
    -1 for user
    1 for admin
    0 if not authorized
    
=cut
#**********************************************************
sub is_authenticated {
    my ( $self, $chat_id ) = @_;

    return - 1 if (exists $user_for_chat_id{$chat_id});
    return 1 if (exists $admin_for_chat_id{$chat_id});

    return 0;
}

#**********************************************************
=head2 send_response($text) - sends text to admin

  Arguments:
    $text -
    
  Returns:
    1 if sent
    
=cut
#**********************************************************
sub send_response {
    my ( $self, $text, $chat_id ) = @_;

    if (! $chat_id) {
        print " Have to send response without \$chat_id. No \n" if ($self->{conf}->{debug});
        return;
    }

    $Bot_API->sendMessage({
        chat_id => $chat_id,
        text    => $text,

        # Object: ReplyKeyboardMarkup
        #    reply_markup => {
        #      resize_keyboard => \1, # \1 = true when JSONified, \0 = false
        #      keyboard        => [
        #        $self->{buttons}
        #      ]
        #    }
    }, sub {});

    return 1;
}

#**********************************************************
=head2 action_show_message($message_obj) - simply prints to console

  Arguments:
    $message_obj -
    
  Returns:
  
  
=cut
#**********************************************************
sub action_show_message {
    my ( $self, $message ) = @_;

    if ($self->{debug} > 5) {
        print Dumper $message;
        return 1;
    }

    eval {
        my $name = ( $message->{from}->{username} ? $message->{from}->{username} : "$message->{from}->{first_name}" );

        print "#$message->{message_id} $name ($message->{from}->{id}) \n$message->{text} \n";
    };
    if ($@) {
        print $@ . "\n";
    }

    return 1;
}


#**********************************************************
=head2 action_greetings($chat_id) - Greets given recipient

  Arguments:
    $chat_id -
    
  Returns:
  
  
=cut
#**********************************************************
sub action_greetings {
    my ( $self, $chat_id ) = @_;

    if (exists $user_for_chat_id{$chat_id}) {
        $self->send_response("Hello, user", $chat_id);
    }
    elsif (exists $admin_for_chat_id{$chat_id}) {
        $self->send_response("Hello, admin", $chat_id);
    }

    return 1;
}

#**********************************************************
=head2 action_unknown_command($message) - actions defined for undefined command

  Arguments:
    $message -
    
  Returns:
  
  
=cut
#**********************************************************
sub action_unknown_command {
    my ( $self, $message ) = @_;

    my $chat_id = $message->{chat}->{id};

    print qq/"LOG_DEBUG", " Telegram ", "Don't know how should respond for: \n $message->{text} "/;

    $self->action_show_message($message);
    $self->send_response("Sorry, can't understand you", $chat_id);

    # Maybe : show commands

    return;
}

#**********************************************************
=head2 authenticate($type, $sid) - authenticates new Telegram receiver

  Arguments:
    $type - u|a
    $sid  -
    
  Returns:
  
  
=cut
#**********************************************************
sub authenticate {
    my ( $self, $type, $sid, $chat_id ) = @_;

    #  if ( $type eq 'u' ) {
    #    my $uid = $Users->web_session_find($sid);
    #
    #    if ( $uid ) {
    #
    #      # Check if already have an account
    #      my $list = $Contacts->contacts_list({
    #        TYPE  => $Contacts::TYPES{TELEGRAM},
    #        VALUE => $chat_id,
    #      });
    #
    #      if ( !$Contacts->{TOTAL} || scalar (@{$list}) == 0 ) {
    #        $Contacts->contacts_add({
    #          UID      => $uid,
    #          TYPE_ID  => $Contacts::TYPES{TELEGRAM},
    #          VALUE    => $chat_id,
    #          PRIORITY => 0,
    #        });
    #      }
    #      $user_for_chat_id{$chat_id} = $uid;
    #      return 1;
    #    }
    #    return 0;
    #  }
    #  elsif ( $type eq 'a' ) {
    #    my $aid = $admin->online_find($sid);
    #
    #    if ( $aid ) {
    #
    #      my $list = $admin->admins_contacts_list({
    #        TYPE  => $Contacts::TYPES{TELEGRAM},
    #        VALUE => $chat_id
    #      });
    #
    #      if ( !$admin->{TOTAL} || scalar (@{$list}) == 0 ) {
    #        $admin->admin_contacts_add({
    #          AID      => $aid,
    #          TYPE_ID  => $Contacts::TYPES{TELEGRAM},
    #          VALUE    => $chat_id,
    #          PRIORITY => 0,
    #        });
    #      }
    #
    #      $admin_for_chat_id{$chat_id} = $aid;
    #      return 1;
    #    }
    #    return 0;
    #  }

    return 1;
}

#**********************************************************
=head2 load_clients() - reads registered contacts from DB (contacts)

=cut
#**********************************************************
sub load_clients {
    my ( $self ) = @_;

    #  my $client_telegram_accounts = $Contacts->contacts_list({
    #    TYPE  => $Contacts::TYPES{TELEGRAM},
    #    VALUE => '_SHOW',
    #    UID   => '_SHOW'
    #  });
    #  foreach ( @{$client_telegram_accounts} ) {
    #    $user_for_chat_id{$_->{value}} = $_->{uid};
    #  }
    #
    #  my $admin_telegram_accounts = $admin->admins_contacts_list({
    #    TYPE  => $Contacts::TYPES{TELEGRAM},
    #    VALUE => '_SHOW',
    #    AID   => '_SHOW'
    #  });
    #  foreach( @{$admin_telegram_accounts} ) {
    #    $admin_for_chat_id{$_->{value}} = $_->{aid};
    #  }

}

1;