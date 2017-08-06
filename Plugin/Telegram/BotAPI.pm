package Abills::Backend::Plugin::Telegram::BotAPI;
use strict;
use warnings 'FATAL' => 'all';

use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

use Abills::Base qw/_bp/;

use JSON;
my JSON $json = JSON->new->utf8(0)->allow_nonref(1);

#**********************************************************
=head2 AUTOLOAD()

=cut
#**********************************************************
sub AUTOLOAD {
  our ($AUTOLOAD);
  my $name = $AUTOLOAD;
  return if ( $name =~ /^.*::[A-Z]+$/ );
  
  my $self = shift;
  $name =~ s/^.*:://;   # strip fully-qualified portion
  
  my $res = 0;
  eval {
    $res = $self->make_request($name, @_);
  };
  return $res;
}


#**********************************************************
=head2 new($attr)

  Arguments:
    $attr -
      token   - auth token
      api_url - (optional), where to send requests
      debug   - debug level
      
  Returns:
    Abills::Backend::Plugin::Telegram::BotAPI instance
  
=cut
#**********************************************************
sub new {
  my $class = shift;
  my ($attr) = @_;
  
  die "No token" unless ( $attr->{token} );
  
  my $self = {
    token    => $attr->{token},
    api_host => 'api.telegram.org',
  };
  
  bless($self, $class);
}

#**********************************************************
=head2 make_request($method_name, $params, $callback) - async request

  Arguments:
    $method_name  - API method
    $params       - hash_ref
    $callback     - coderef, if given,
    
  Returns:
  
  
=cut
#**********************************************************
sub make_request {
  my ($self, $method_name, $params, $callback) = @_;
  
  my $endpoint = $self->{api_host};
  
  my $waiter;
  if ( !$callback ) {
    $waiter = AnyEvent->condvar();
  }
  
  tcp_connect ($endpoint, 443,
    sub {
      my ($fh) = @_
        or die "unable to connect: $!";
      
      my $handle; # avoid direct assignment so on_eof has it in scope.
      $handle = AnyEvent::Handle->new(
        fh       => $fh,
        tls      => 'connect',
        tls_ctx  => {
          sslv3          => 0,
          verify         => 1,
          session_ticket => 1,
        },
        on_error => sub {
          $_[0]->destroy;
        },
        on_eof   => sub {
          $handle->destroy; # destroy handle
          AE::log info => "Done.";
        },
        on_read  => sub {
          my $hdl = shift;
          my $raw_content = $hdl->{rbuf};
          
          my (undef, $json_content) = split(/[\r\n]{4}/m, $raw_content);
          
          my $response = '';
          eval {
            $response = $json->decode($json_content);
          };
          if ( $@ ) {
            _bp('raw json', $json_content);
            _bp('error', $@);
            my $res = { error => $@, ok => 0, type => 'on_read' };
            if ( !$callback ) {
              return $res;
            }
            else {
              $callback->($res);
            }
          }
          
          $handle->destroy();
          if ( !$callback ) {
            $waiter->send($response);
          }
          else {
            $callback->($response);
          }
        }
      );
      
      my $params_encoded = '';
      eval {
        $params_encoded = $json->encode($params);
      };
      if ( $@ ) {
        _bp('params', $params);
        _bp('error', $@);
        my $res = { error => $@, ok => 0, type => 'on_write' };
        if ( !$callback ) {
          return $res;
        }
        else {
          $callback->($res);
        }
      }
      
      my $length = length $params_encoded;
      _bp('sent params', $params_encoded) if ( $self->{debug} && $self->{debug} > 1 );
      #      $handle->push_write("HTTP 1.1\nGET /bot$self->{token}/$method_name\n\n");
      $handle->push_write(qq{GET /bot$self->{token}/$method_name HTTP/1.0
Host: $endpoint
Pragma: no-cache
Cache-Control: no-cache
Content-Length: $length
Content-Type: application/json

$params_encoded});
    }
  );
  if ( !$callback ) {
    return $waiter->recv();
  }
  return 1;
  
}

sub DESTROY {

}

1;