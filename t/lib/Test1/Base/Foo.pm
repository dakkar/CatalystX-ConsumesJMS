package Test1::Base::Foo;
use Moose;
extends 'Catalyst::Component';
with 'CatalystX::ControllerBuilder';

sub _kind_name { 'Foo' }

sub _wrap_code {
    my ($self,$appclass,$url,$action,$route) = @_;
    my $code = $route->{code};

    return sub {
        my ($controller,$c) = @_;

        my $data = $c->req->data;
        my $headers = $c->req->headers;

        $self->$code($data,$headers);

        $c->res->body('nothing');
        return;
    }
}

1;
