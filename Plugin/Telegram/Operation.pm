package Abills::Backend::Plugin::Telegram::Operation;
use strict;
use warnings FATAL => 'all';


#**********************************************************
=head2 new($attr) - constructor for Abills::Backend::Plugin::Telegram::Operation

  Arguments:
    $attr - hash_ref
      CHAT_ID    -
      TYPE       - string, 'AID' or 'UID'
      NAME       - operation_name (human readable)
      ON_START   - coderef
      ON_MESSAGE - handler for message
      ON_FINISH  - coderef

  Returns:
    $self - Abills::Backend::Plugin::Telegram::Operation instance
    
=cut
#**********************************************************
sub new {
  my $class = shift;
  my ($attr) = @_;
  
  my $self = \%{$attr};
  
  return 0 unless ( $attr->{CHAT_ID} || $attr->{ON_MESSAGE} );
  
  bless($self, $class);
  
  return $self;
}

#**********************************************************
=head2 start() - run ON_START

  Arguments:
     -
    
  Returns:
  
  
=cut
#**********************************************************
sub start {
  my ($self) = @_;
  
  if ( $self->{ON_START} ) {
    $self->{ON_START}->($self);
  }
  
  return 1;
}

#**********************************************************
=head2 on_message($message) - handle new client message

  Arguments:
    $message -
    
  Returns:
    boolean - 1 if have to finish operation now
    
=cut
#**********************************************************
sub on_message {
  my ($self, $message) = @_;
  return $self->{ON_MESSAGE}->($self, $message);
}

#**********************************************************
=head2 on_finish()

=cut
#**********************************************************
sub on_finish {
  my ($self) = @_;
  
  if ( $self->{ON_FINISH} ) {
    $self->{ON_FINISH}->($self);
  }
  
  return 1;
}

1;