package CatalystX::ConsumesJMS::WithDefault;
use Moose::Role;

# ABSTRACT: sub-role of L<CatalystX::ConsumesJMS> that provides
# handling C<default> to created controllers

=head1 SYNOPSIS

  package MyApp::Base::Stuff;
  use Moose;
  extends 'Catalyst::Component';
  with 'CatalystX::ConsumesJMS::WithDefault';

  sub _kind_name {'Stuff'}
  sub _wrap_code {
    my ($self,$c,$destination_name,$msg_type,$route) = @_;
    return $route->{code}
  }
  sub _default_action {
    my ($self,$c,$destination_name,$msg_type,$route) = @_;
    return sub { ... }
  }

=head1 DESCRIPTION

If you use L<CatalystX::ConsumesJMS>, and your application receives a
message of a type it was not expecting, the application will return an
error response. You may want to do something special instead.

You could, of course, write an explicit C<< sub default :Default {
... } >> in every controller, but since the whole point of this
distribution is to avoid having to write controllers by hand, this
role may help.

Every time a controller is generated, a default action will be
installed. The body of the action is whatever L</_default_action>
returns.

B<NOTE>: the default action will only be installed once per
controller. If you have multiple components (maybe even of different
"kinds") routing from the same destination, which one gets to install
the default action is not defined. It is to be considered good
practice, when using this role, to install the same code for the
default action in every controller.

=cut

with 'CatalystX::ConsumesJMS';

=head1 Required methods

=cut

=head2 C<_default_action>

This method is called almost the same way as C<_wrap_code>. It
receives:

=over 4

=item *

the Catalyst application as passed to C<expand_modules>

=item *

the destination name

=item *

the message type

=item *

the value from the C<routes> corresponding to the destination name and
message type, that includes the C<code> slot (see
L<CatalystX::ConsumesJMS/Routing> ).

=back

B<NOTE>: as said above, you should not really use any of these
parameter, except maybe the application class.

The coderef returned will be invoked as a Catalyst action for each
received message, which means it will get:

=over 4

=item *

the controller instance (you should rarely need this)

=item *

the Catalyst application context

=back

It can get the de-serialized message by calling C<< $c->req->data >>,
and the request headers (a L<HTTP::Headers> object) by calling C<<
$c->req->headers >>.

It can set the message to serialise in the response by setting C<<
$c->stash->{message} >>, and the headers by calling C<<
$c->res->header >>.

=cut

requires '_default_action';

around '_generate_controller_package' => sub {
    my ($orig,$self,$appname,$destination_name,
        $msg_type,$config,$route) = @_;

    my $controller_pkg=$self->$orig($appname,$destination_name,
                                    $msg_type,$config,$route);

    my $code = $self->_default_action($appname,$destination_name,
                                      $msg_type,$route);

    $controller_pkg->meta->add_after_method_modifier(
        'register_actions' => sub {
            my ($self_controller,$c) = @_;

            my $action = $self_controller->create_action(
                name => 'default',
                code => $code,
                reverse => "$destination_name/default",
                namespace => $destination_name,
                class => $controller_pkg,
                attributes => {
                    Default => [undef],
                },
            );
            $c->dispatcher->register($c,$action);

        }
    );

    return $controller_pkg;
};

1;
