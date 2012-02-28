package CatalystX::ConsumesStomp;
use Moose::Role;

# ABSTRACT: role for components providing Catalyst actions

=head1 SYNOPSIS

  package MyApp::Base::Stuff;
  use Moose;
  extends 'Catalyst::Component';
  with 'CatalystX::ConsumesStomp';

  sub _kind_name {'Stuff'}
  sub _wrap_code { return $_[2] }
  sub _wrap_validator { return $_[2] }

Then:

  package MyApp::Stuff::One;
  use Moose;
  extends 'MyApp::Base::Stuff';

  sub routes {
    return {
      my_input_destination => {
        my_message_type => {
          validator => \&validator_method,
          code => \&my_consume_method,
        },
        ...
      },
      ...
    }
  }

  sub validator_sub {
    my ($self,$message,$headers) = @_;

    return 1; # better do some smarter validation
  }

  sub my_consume_method {
    my ($self,$message,$headers) = @_;

    # do something
  }

Also, remember to tell L<Catalyst> to load your C<Stuff> components:

  <setup_components>
   search_extra ::Stuff
  </setup_components>

=head1 DESCRIPTION

This role is to be used to define base classes for your Catalyst-based
Stomp conusmer applications. It's I<not> to be consumed directly by
application components.

=head2 Routing

Subclasses of your component base specify which messages they are
interested in, by writing a C<routes> sub, see the synopsis for an
example.

They can specify as many destinations and message types as they want /
need, and they can re-use the same C<validator> and C<code> values as
many times as needed.

The main limitation is that you can't have two components using the
exact same destination / type pair (even if they derive from different
base classes!). If you do, the results are undefined.

It is possible to alter the destination name via configuration, like:

  <Stuff::One>
    my_input_destination the_actual_destination_name
  </Stuff::One>

=head2 The validator

The value paired to the C<validator> will be wrapped via the
C</_wrap_validator> method that the consuming class has to provide.

The coderef returned by such call will be invoked as a method on the
subclass object, passing:

=over 4

=item *

the controller instance (you should rarely need this)

=item *

the Catalyst application context

=item *

the de-serialized message body

=item *

the request headers (a L<HTTP::Headers> object)

=back

The wrapped coderef should return a true value if the message passes
the validation, or a false value if it does not. Throwing an exception
is an alternative way of signaling that the message failed to
validate.

If a message is received (in that destination with that type) that
does not pass validation, the message will be rejected (and the
exception, if any, logged).

=head2 The "code"

The coderef paired to the C<code> key will be wrapped via the
L</_wrap_code> function that the consuming class has to provide.

The coderef so wrapped will be invoked as a method on the subclass
object, passing:

=over 4

=item *

the controller instance (you should rarely need this)

=item *

the Catalyst application context

=item *

the (validated) de-serialized message

=item *

the request headers (a L<HTTP::Headers> object)

=back

You can do whatever you need in this coderef.

=cut

sub routes {
    return {}
}

=head1 Required methods

=head2 C<_kind_name>

As in the synopsis, this should return a string that, in the names of
the classes deriving from the consuming class, separates the
"application name" from the "component name".

These names are mostly used to access the configuration.

=cut

requires '_kind_name';

=head2 C<_wrap_code>

This methods is called with:

=over 4

=item *

the Catalyst application as passed to C<register_actions>

=item *

the coderef specified in the C<routes>, slot C<code> (see L</Routing>
above)

=back

The coderef returned will be invoked for each received message,
passing:

=over 4

=item *

the controller instance (you should rarely need this)

=item *

the Catalyst application context

=item *

the (validated) de-serialized message

=item *

the request headers (a L<HTTP::Headers> object)

=back

=cut

requires '_wrap_code';

=head2 C<_wrap_validator>

This methods is called with:

=over 4

=item *

the Catalyst application as passed to C<register_actions>

=item *

the value specified in the C<routes>, slot C<validator> (see
L</Routing> above)

=back

The coderef returned will be invoked for each received message,
passing:

=over 4

=item *

the controller instance (you should rarely need this)

=item *

the Catalyst application context

=item *

the de-serialized message

=item *

the request headers (a L<HTTP::Headers> object)

=back

It should return a true value if the message passes the validation, or
a false value if it does not. Throwing an exception is an alternative
way of signaling that the message failed to validate.

=cut

requires '_wrap_validator';

=head1 Implementation Details

B<HERE BE DRAGONS>.

This role should be consumed by sub-classes of C<Catalyst::Component>.

The consuming class is supposed to be used as a base class for
application components (see the L</SYNOPSIS>, and make sure to tell
Catalyst to load them!).

Since these components won't be in the normal Model/View/Controller
namespaces, we need to modify the C<COMPONENT> method to pick up the
correct configuration options.

=cut

around COMPONENT => sub {
    my ($orig,$class,$appclass,$config) = @_;

    my $kind_name = $class->_kind_name;

    my ($appname,$basename) = ($class =~ m{^((?:\w|:)+)::\Q$kind_name\E::(.*)$});
    $config = $appclass->config->{"${kind_name}::${basename}"} || {};

    return $class->$orig($appclass,$config);
};

=pod

We hijack the C<expand_modules> method to generate various bits of
Catalyst code on the fly.

If the component has a configuration entry C<enabled> with a false
value, it is ignored, thus disabling it completely.

=cut

sub expand_modules {
    my ($self,$component,$config) = @_;

    my $class=ref($self);our $VERSION;

    my $kind_name = $class->_kind_name;

    my ($appname,$basename) = ($class =~ m{^((?:\w|:)+)::\Q$kind_name\E::(.*)$});

    my $pre_routes = $class->routes;

    if (defined $config->{enabled} && !$config->{enabled}) {
        return;
    }

    my %routes;
    for my $destination_name (keys %$pre_routes) {
        my $real_name = $config->{$destination_name} // $destination_name;
        my $route = $pre_routes->{$destination_name};
        @{$routes{$real_name}}{keys %$route} = values %$route;
    }

    my @result;

    for my $destination_name (keys %routes) {
        my $route = $routes{$destination_name};
        my $pkg_safe_destination_name = $destination_name;
        $pkg_safe_destination_name =~ s{\W+}{_}g;

=pod

We generate a controller package, inheriting from
L<Catalyst::Controller::ActionRole>, called
C<${appname}::Controller::${destination_name}>.

Inside this package, we set the C<action_namespace> attribute to
return the destination name.

=cut

        my $controller_pkg = "${appname}::Controller::${pkg_safe_destination_name}";

        if (!Class::MOP::is_class_loaded($controller_pkg)) {
            Moose::Meta::Class->create(
                $controller_pkg => (
                    version => $VERSION,
                    superclasses => ['Catalyst::Controller::JMS'],
                    attributes => [
                        Class::MOP::Attribute->new(
                            action_namespace => (
                                default => $destination_name,
                                reader => 'action_namespace',
                            )
                        ),
                    ],
                    methods => {
                    },
                )
            );
        }

=pod

In addition, we add an C<after> method modifier to the
C<register_actions> method inherited from C<Catalyst::Controller>, to
create the actions for each message type. Each action will have the
attribute C<MessageTarget>, see L<Catalyst::Controller::JMS>.

Each action's code is obtained by calling L</_wrap_code>.

=cut

        $controller_pkg->meta->add_after_method_modifier(
            'register_actions' => sub {
                my ($self_controller,$c) = @_;

                for my $type (keys %$route) {

                    my $coderef = $self->_wrap_code(
                        $c,
                        $route->{$type}{code},
                    );
                    my $action = $self_controller->create_action(
                        name => $type,
                        code => $coderef,
                        reverse => "$destination_name/$type",
                        namespace => $destination_name,
                        class => $controller_pkg,
                        attributes => {
                             => [
                                 MessageTarget => [$type],
                             ],
                        },
                    );
                    $c->dispatcher->register($c,$action);
                }
            }
        );
        push @result,$controller_pkg;
    }

    return @result;
}

=begin Pod::Coverage

routes

expand_modules

=end Pod::Coverage

1;
