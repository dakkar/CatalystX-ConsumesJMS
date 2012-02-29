package Test1::Base::Foo;
use Moose;
extends 'Catalyst::Component';
with 'CatalystX::ConsumesStomp';

sub _kind_name { 'Foo' }

sub _wrap_code { return $_[2]->{code} }

1;
