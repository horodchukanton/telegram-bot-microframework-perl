package Plugin::Telegram::ModuleInterface;
use strict;
use warnings FATAL => 'all';

use Plugin::Telegram::Operation;

#**********************************************************
=head2 process_data()
  
  Arguments:
    $api      - API for Telegram plugin
    $data_raw - data as got from callback_query
    $attr     - hash_ref
      SENDER - hash_ref
        CHAT_ID - chat_id
        TYPE    - string, 'AID' or 'UID'
  
  Returns:
    0 on error
    instance of Plugin::Telegram::Operation
    
=cut
#**********************************************************
sub process_data {
    my Plugin::Telegram $api = shift;

    my ( $data_arr, $attr ) = @_;
    return if (! $attr->{CHAT_ID} || ! $data_arr);

    my @data = ();
    if (ref $data_arr eq 'ARRAY') {
        @data = @{$data_arr};
    }
    else {
        @data = split(':', $data_arr);
    }

    my $operation = shift @data;

    my $client_type = $attr->{CLIENT_TYPE};
    my $client_id = $attr->{CLIENT_ID};

    my $save_reply = ( $client_type eq 'UID' )
        ? sub {
        my ( $msg_id, $text ) = @_;
        msgs_user_reply($msg_id, {
            REPLY_TEXT => $text,
            UID        => $client_id,
            #        STATE => 6
        });
    }
        : sub {
        my ( $msg_id, $text ) = @_;
        msgs_admin_reply($msg_id, {
            REPLY_TEXT => $text,
            AID        => $client_id,
        });
    };

    if ($operation && $operation eq 'REPLY') {
        my $msg_id = shift @data;

        # Create new operation
        my $reply_operation = Plugin::Telegram::Operation->new({
            NAME       => 'Reply',
            MSGS_ID    => $msg_id,
            ON_START   => sub {
                $api->send_response("Operation started", $attr->{CHAT_ID});
            },
            ON_MESSAGE => sub {
                my ( $self, $message ) = @_;
                $save_reply->($msg_id, $message->{text});
                $api->send_response("Reply goes to : " . ( $msg_id || '' ), $attr->{CHAT_ID});
                return 1;
            },
            ON_FINISH  => sub {
                $api->send_response("Operation finished", $attr->{CHAT_ID});
            },
            %{$attr},

        });

        return $reply_operation;
    }

    return 0;
}

1;