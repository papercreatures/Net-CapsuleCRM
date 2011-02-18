package Net::CapsuleCRM;

use strict;
use warnings;
use Moo;
use Sub::Quote;
use Method::Signatures;
use JSON::XS;
use HTTP::Request::Common;
use XML::Simple;

=head1 SYNOPSIS

Connect to the Capsule API (www.capsulecrm.com)

my $foo = Net::CapsuleCRM->new(
  token => 'xxxx',
  target_domain => 'test.capsulecrm.com',
  debug => 0,
);

=head2 login

This sets up the initial OAuth handshake and returns the login URL. This
URL has to be clicked by the user and the the user then has to accept
the application in xero. 

Xero then redirects back to the callback URL defined with
C<$self-E<gt>callback_url>. If the user already accepted the application the
redirect may happen without the user actually clicking anywhere.

=cut

has 'debug' => (is => 'rw', predicate => 'is_debug');
has 'error' => (is => 'rw', predicate => 'has_error');
has 'token' => (is => 'rw', required => 1);
has 'ua' => (is => 'rw', 
  default => sub { LWP::UserAgent->new( agent => 'Perl Net-CapsuleCRM'); } );
has 'target_domain' => (is => 'rw', default => 'test.capsulecrm.com')
has 'xmls' => ( is => 'rw', default => sub { return XML::Simple->new(
  NoAttr => 1, KeyAttr => [], XMLDecl => 1, SuppressEmpty => 1, ); }
);

method endpoint_uri { return 'https://' . $self->target_domain . '/api/'; }

method _talk($command,$method,$content?) {
  my $uri = URI->new($self->endpoint_uri);
  $uri->path("api/$command");

  $self->ua->credentials( 
    $uri->host . ':'.$uri->port,
    'seamApp',
    $self->token => 'x'
  );
  
  print "$uri\n" if $self->debug;
  my $res;
  my $type = ref $content  eq 'HASH' ? 'json' : 'xml';
  if($method =~ /get/i){
    if(ref $content eq 'HASH') {
      $uri->query_form($content);
    }
    $res = $self->ua->request(
      GET $uri, #content is ID in this instance.
      Accept => 'application/json', 
      Content_Type => 'application/json',
    );
  } else {
    #$content = $self->_template($content) if $content;
    if($type eq 'json') {
      print "Encoding as JSON\n" if $self->debug;
      $content = $self->xmls->XMLout($content, RootName => $command);
    } else {
      #otherwise XML
      print "Encoding as XML\n" if $self->debug;
    }

    $res = $self->ua->request(
      POST $uri,
      Accept => 'text/xml', 
      Content_Type => 'text/xml',
      Content => $content,
    );

  }
  
  if ($res->is_success) {
    print "Server said: ", $res->status_line, "\n" if $self->debug;
    if($res->status_line =~ /^201/) {
      return (split '/', $res->header('Location'))[-1]
    } else {
      if($type eq 'json') {
        return decode_json $res->content;
      } elsif($res->content) {
        return XMLin $res->content;
      } else {
        return 1;
      }
    }
  } else {
    $self->error($res->status_line);
    warn $self->error;
  }
  
}

method find_party_by_email($email) {
  my $res = $self->_talk('party', 'GET', {
    email => $email,
    start => 0,
  });
  return $res->{'parties'}->{'person'}->{'id'} || undef;
}

method find_party($id) {
  my $res = $self->_talk('party/'.$id, 'GET', $id);
  return $res->{'parties'}->{'person'}->{'id'} || undef;
}

method create_person($data) {
  return $self->_talk('person', 'POST', $data);
}

method create_organisation($data) {
  return $self->_talk('organisation', 'POST', $data);
}

method add_tag($id, @tags) {
  # my $data = $self->xmls->XMLout(
  #   { tag => [ map { name => $_ }, @tags ] }, RootName => 'tags'
  # );
  foreach(@tags) {
    $self->_talk("party/$id/tag/$_", 'POST');
  }
}


1;