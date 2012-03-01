package Test2::Base::Foo;
use Moose;
extends 'Catalyst::Component';
with 'CatalystX::ConsumesJMS::WithDefault';

sub _kind_name { 'Foo' }

sub _wrap_code {
    my ($self,$appclass,$dest,$type,$route) = @_;
    my $code = $route->{code};

    return sub {
        my ($controller,$c) = @_;

        my $message = $c->req->data;
        my $headers = $c->req->headers;

        $self->$code($message,$headers);

        $c->stash->{message} ||= {no=>'thing'};
        $c->res->header('X-Reply-Address'=>'reply-address');
        return;
    }
}

sub _default_action {
    my ($self,$appclass,$dest,$type,$route) = @_;

    return sub {
        my ($self_controller,$c) = @_;

        $c->stash->{message} ||= {default=>'response'};
        $c->res->header('X-Reply-Address'=>'reply-address');
    };
}

1;
