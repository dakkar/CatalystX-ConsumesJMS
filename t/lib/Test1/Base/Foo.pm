package Test1::Base::Foo;
use Moose;
extends 'Catalyst::Component';
with 'CatalystX::ConsumesStomp';

sub _kind_name { 'Foo' }

sub _wrap_code {
    my ($self,$appclass,$route) = @_;
    my $code = $route->{code};

    return sub {
        my ($controller,$c) = @_;

        my $message = $c->req->data;
        my $headers = $c->req->headers;

        $self->$code($message,$headers);

        $c->stash->{message} = {no=>'thing'};
        $c->res->header('X-STOMP-Reply-Address'=>'reply-address');
        return;
    }
}

1;
