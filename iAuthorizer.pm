package Business::OnlinePayment::iAuthorizer;

# $Id: iAuthorizer.pm,v 1.2 2003/08/12 22:00:05 db48x Exp $

use strict;
#use Carp;
use Business::OnlinePayment;
use Net::SSLeay qw/make_form post_https make_headers/;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;

@ISA = qw(Exporter AutoLoader Business::OnlinePayment);
@EXPORT = qw();
@EXPORT_OK = qw();
$VERSION = '0.1';

sub set_defaults {
    my $self = shift;

    $self->server('tran1.iAuthorizer.net');
    $self->port('443');
    $self->path('/trans/postto.asp');
}

sub map_fields {
    my($self) = @_;

    my %content = $self->content();

    # ACTION MAP
    my %actions = ('normal authorization' => '5',
                   'authorization only'   => '6',
                   'credit'               => '0',
                   'post authorization'   => '2',
                  );
    $content{'action'} = $actions{lc($content{'action'})} || $content{'action'};

    # stuff it back into %content
    $self->content(%content);
}

sub remap_fields {
    my($self,%map) = @_;

    my %content = $self->content();
    foreach(keys %map) {
        $content{$map{$_}} = $content{$_};
    }
    $self->content(%content);
}

sub get_fields {
    my($self,@fields) = @_;

    my %content = $self->content();
    my %new = ();
    foreach(grep defined $content{$_}, @fields) { $new{$_} = $content{$_}; }
    return %new;
}

sub submit {
    my($self) = @_;

    $self->map_fields();
    $self->remap_fields(
        EntryMethod    => 'Entrymethod',
        login          => 'MerchantCode',
        password       => 'MerchantPWD',
        serial         => 'MerchantSerial',
        action         => 'Trantype',
        amount         => 'amount',
        invoice_number => 'invoicenum',
	order_number   => 'referencenum',
	auth_code      => 'appcode',
        customer_id    => 'customer',
        address        => 'Address',
        zip            => 'ZipCode',
        card_number    => 'ccnumber',
        cvv2           => 'CVV2',
    );

#    if ($self->transaction_type() eq "ECHECK") {
#        if ($self->{_content}->{customer_org} ne '') {
#            $self->required_fields(qw/type login password amount routing_code
#                                  account_number account_type bank_name
#                                  account_name account_type check_type
#                                  customer_org customer_ssn/);
#        } else {
#            $self->required_fields(qw/type login password amount routing_code
#                                  account_number account_type bank_name
#                                  account_name account_type check_type
#                                  license_num license_state license_dob/);
#        }
#    } elsif ($self->transaction_type() eq 'CC' ) {
#      if ( $self->{_content}->{action} eq 'PRIOR_AUTH_CAPTURE' ) {
#        $self->required_fields(qw/type login password action amount
#                                  card_number expiration/);
#      } else {
#        $self->required_fields(qw/type login password action amount last_name
#                                  first_name card_number expiration/);
#      }
#    } else {
#        Carp::croak("AuthorizeNet can't handle transaction type: ".
#                    $self->transaction_type());
#    }

    $self->required_fields(qw/MerchantSerial MerchantCode MerchantPWD action ccnumber expiration  amount/);

    my %post_data = $self->get_fields(qw/MerchantSerial MerchantCode MerchantPWD ccnumber ExpYear ExpMonth 
                                         Trantype Entrymethod amount invoicenum ordernum Zipcode Address CVV2 CF/);

    ($post_data{'expMonth'}, $post_data{'expYear'}) = split('/', $self->{_content}->{'expiration'});

    $post_data{'Entrymethod'} = 0;   # hand entered, as opposed to swiped through a card reader
    $post_data{'CF'} = 'ON';         # return comma-delimited data

    my $pd = make_form(%post_data);
    my $s = $self->server();
    my $p = $self->port();
    my $t = $self->path();
    my $r = $self->{_content}->{referer};
    my($page,$server_response,%headers) = post_https($s,$p,$t,$r,$pd);

    my @col = split(',', $page);

    $self->server_response($page);
    if($col[0] eq "0" ) {
        $self->is_success(1);
        $self->result_code($col[1]);
        $self->authorization($col[1]);
    } else {
        $self->is_success(0);
        $self->result_code($col[1]);
        $self->error_message($col[2]);
        unless ($self->result_code()) { 
          $self->error_message("&lt;no response code, debug info follows&gt;\n".
            "HTTPS response:\n  $server_response\n\n".
            "HTTPS headers:\n  ".
              join("\n  ", map { "$_ => ". $headers{$_} } keys %headers ). "\n\n".
            "POST Data:\n  ".
              join("\n  ", map { "$_ => ". $post_data{$_} } keys %post_data ). "\n\n".
            "Raw HTTPS content:\n  $page"
          );
        }
    }
}

1;
__END__

=head1 NAME

Business::OnlinePayment::iAuthorizer - iAuthorizer.net backend for Business::OnlinePayment

=head1 SYNOPSIS

  use Business::OnlinePayment;

  my $tx = new Business::OnlinePayment("iAuthorizer");
  $tx->content('login'       => '...', # login, password, and serial for your account
               'password'    => '...',   
               'serial'      => '...',
               'action'      => 'Normal Authorization',
               'card_number' => '4012888888881',  # test card       
               'expiration'  => '05/05',
               'amount'      => '1.00',
               'address'     => '123 Anystreet',
               'zip'         => '12345',
               'cvv2'        => '1234',
              );

  $tx->submit();

  if($tx->is_success()) {
      print "Card processed successfully: ".$tx->authorization."\n";
  } else {
      print "Card was rejected: ".$tx->error_message."\n";
  }

=head1 SUPPORTED TRANSACTION TYPES

=head2 All Credit Cards

Content required: login, password, serial, action, amount, card_number, expiration.

The type field is never required, as the module does not support 
check transactions.

=head1 DESCRIPTION

For detailed information see L<Business::OnlinePayment>.

=head1 NOTE

Business::OnlinePayment::iAuthorizer uses the direct response method,
and does not support the post back response method.

To settle an authorization-only transaction (where you set action to
'Authorization Only'), submit the nine-digit transaction id code in
the field "order_number" with the action set to "Post Authorization".
You can get the transaction id from the authorization by calling the
order_number method on the object returned from the authorization.
You must also submit the amount field with a value less than or equal
to the amount specified in the original authorization.

=head1 COMPATIBILITY

This module implements iAuthorizer.net's API, but does not support 
check transactions or the 'post back' response method.

This module has not yet been certified by iAuthorizer.

=head1 AUTHOR

Copyright © 2003 Daniel Brooks <db48x@yahoo.com>

Many thanks to Jason Kohles and Ivan Kohler, who wrote and maintain
Business::OnlinePayment::AuthorizeNet, which I borrowed heavily from
while building this module.

The iAuthorizer.net service is required before this module will function, however the module itself is free software and may be redistributed and/or 
modified under the same terms as Perl itself.

=head1 SEE ALSO

L<Business::OnlinePayment>.

=cut

