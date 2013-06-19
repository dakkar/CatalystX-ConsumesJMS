package CatalystX::ConsumesJMS;
use Moose::Role;
use namespace::autoclean;
with 'CatalystX::ControllerBuilder';
use Catalyst::Utils ();

# ABSTRACT: role for components providing Catalyst actions consuming messages

=head1 SYNOPSIS

  package MyApp::Base::Stuff;
  use Moose;
  extends 'Catalyst::Component';
  with 'CatalystX::ConsumesJMS';

  sub _kind_name {'Stuff'}
  sub _wrap_code {
    my ($self,$c,$destination_name,$msg_type,$route) = @_;
    my $code = $route->{code};
    my $extra_config = $route->{extra_config};
    return sub {
      my ($controller,$ctx) = @_;
      my $message = $ctx->req->data;
      $self->$code($message);
    }
  }

Then:

  package MyApp::Stuff::One;
  use Moose;
  extends 'MyApp::Base::Stuff';

  sub routes {
    return {
      my_input_destination => {
        my_message_type => {
          code => \&my_consume_method,
          extra_config => $whatever,
        },
        ...
      },
      ...
    }
  }

  sub my_consume_method {
    my ($self,$message) = @_;

    # do something
  }

Also, remember to tell L<Catalyst> to load your C<Stuff> components:

  <setup_components>
   search_extra [ ::Stuff ]
  </setup_components>

=head1 DESCRIPTION

This role is to be used to define base classes for your Catalyst-based
JMS / STOMP consumer applications. It's I<not> to be consumed directly
by application components.

=head2 Routing

Subclasses of your component base specify which messages they are
interested in, by writing a C<routes> sub, see the synopsis for an
example.

They can specify as many destinations and message types as they want /
need, and they can re-use the C<code> values as many times as needed.

The main limitation is that you can't have two components using the
exact same destination / type pair (even if they derive from different
base classes!). If you do, the results are undefined.

It is possible to alter the destination name via configuration, like:

  <Stuff::One>
   <routes_map>
    my_input_destination the_actual_destination_name
   </routes_map>
  </Stuff::One>

You can also do this:

  <Stuff::One>
   <routes_map>
    my_input_destination the_actual_destination_name
    my_input_destination another_destination_name
   </routes_map>
  </Stuff::One>

to get the consumer to consume from two different destinations without
altering the code.

=head2 The "code"

The hashref specified by each destination / type pair will be passed
to the L</_wrap_code> function (that the consuming class has to
provide), and the coderef returned will be installed as the action to
invoke when a message of that type is received from that destination.

The action, like all Catalyst actions, will be invoked passing:

=over 4

=item *

the controller instance (you should rarely need this)

=item *

the Catalyst application context

=back

You can do whatever you need in this coderef, but the synopsis gives a
generally useful idea. You can find more examples of use at
https://github.com/dakkar/CatalystX-StompSampleApps

=cut

=head1 Required methods

=head2 C<_kind_name>

As in the synopsis, this should return a string that, in the names of
the classes deriving from the consuming class, separates the
"application name" from the "component name".

These names are mostly used to access the configuration.

=head2 C<_wrap_code>

This method is called with:

=over 4

=item *

the Catalyst application as passed to C<register_actions>

=item *

the destination name

=item *

the message type

=item *

the value from the C<routes> corresponding to the destination name and
message type slot (see L</Routing> above)

=back

The coderef returned will be invoked as a Catalyst action for each
received message, which means it will get:

=over 4

=item *

the controller instance (you should rarely need this)

=item *

the Catalyst application context

=back

You can get the de-serialized message by calling C<< $c->req->data >>.
The JMS headers will most probably be in C<< $c->req->env >> (or C<<
$c->engine->env >> for older Catalyst), all keys namespaced by
prefixing them with C<jms.>. So to get all JMS headers you could do:

   my $psgi_env = $c->req->can('env')
                  ? $c->req->env
                  : $c->engine->env;
   my %headers = map { s/^jms\.//r, $psgi_env->{$_} }
                 grep { /^jms\./ } keys $psgi_env;

You can set the message to serialise in the response by setting C<<
$c->stash->{message} >>, and the headers by calling C<<
$c->res->header >> (yes, incoming and outgoing data are handled
asymmetrically. Sorry.)

=head2 C<_controller_base_classes>

List (not arrayref!) of class names that the controllers generated by
L</_generate_controller_package> should inherit from. Defaults to
C<'Catalyst::Controller::JMS'>.

=cut

sub _controller_base_classes { 'Catalyst::Controller::JMS' }

=head2 C<_controller_roles>

List (not arrayref!) of role names that should be applied to the
controllers created by L</_generate_controller_package>. Defaults to
the empty list.

=head2 C<_action_extra_params>

  my %extra_params = $self->_action_extra_params(
                      $c,$url,
                      $action_name,$route->{$action_name},
                     );

You can override this method to provide additional arguments for the
C<create_action> call inside
C</_generate_register_action_modifier>. For example you could return:

  attributes => { MySpecialAttr => [ 'foo' ] }

to set that attribute for all generated actions. Defaults to:

  attributes => { 'Path' => ["$url/$action_name"] }

to make all the action "local" to the generated controller (i.e. they
will be invoked for requests to C<< $url/$action_name >>).

=cut

sub _action_extra_params {
    my ($self,$c,$destination,$type,$route) = @_;
    return attributes => { MessageTarget => [$type] };
}

=begin Pod::Coverage

routes

expand_modules

=end Pod::Coverage

=cut

1;
