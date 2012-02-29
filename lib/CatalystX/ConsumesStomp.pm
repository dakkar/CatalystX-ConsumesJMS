package CatalystX::ConsumesStomp;
use Moose::Role;

# ABSTRACT: role for components providing Catalyst actions

=head1 SYNOPSIS

  package MyApp::Base::Stuff;
  use Moose;
  extends 'Catalyst::Component';
  with 'CatalystX::ConsumesStomp';

  sub _kind_name {'Stuff'}
  sub _wrap_code { return $_[2]->{code} }

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
need, and they can re-use the C<code> values as many times as needed.

The main limitation is that you can't have two components using the
exact same destination / type pair (even if they derive from different
base classes!). If you do, the results are undefined.

It is possible to alter the destination name via configuration, like:

  <Stuff::One>
    my_input_destination the_actual_destination_name
  </Stuff::One>

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

the de-serialized message

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

a value from the C<routes>, that includes the C<code> slot (see
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

=cut

requires '_wrap_code';

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

    my $class=ref($self);

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

=pod

We generate a controller package by calling
L</_generate_controller_package>, and we add an C<after> method
modifier to the C<register_actions> method inherited from
C<Catalyst::Controller>, to create the actions for each message
type. The modifier is generated by calling
L</_generate_register_action_modifier>.

=cut

        my $controller_pkg = $self->_generate_controller_package(
            $appname,$destination_name,$config,$route,
        );

        $controller_pkg->meta->add_after_method_modifier(
            'register_actions' =>
                $self->_generate_register_action_modifier(
                    $appname,$destination_name,
                    $controller_pkg,
                    $config,$route,
                ),
        );

        push @result,$controller_pkg;
    }

    $_->meta->make_immutable for @result;

    return @result;
}

=method C<_generate_controller_package>

  my $pkg = $self->_generate_controller_package(
                $appname,$destination,
                $config,$route);

Generates a controller package, inheriting from
L<Catalyst::Controller::ActionRole>, called
C<${appname}::Controller::${destination_name}>.

Inside this package, we set the C<namespace> config slot to the
destination name.

=cut

sub _generate_controller_package {
    my ($self,$appname,$destination_name,$config,$route) = @_;

    my $pkg_safe_destination_name = $destination_name;
    $pkg_safe_destination_name =~ s{\W+}{_}g;

    my $controller_pkg = "${appname}::Controller::${pkg_safe_destination_name}";

    our $VERSION; # get the global, set by Dist::Zilla

    if (!Class::MOP::is_class_loaded($controller_pkg)) {
        my $meta = Moose::Meta::Class->create(
            $controller_pkg => (
                version => $VERSION,
                superclasses => ['Catalyst::Controller::JMS'],
            )
        );
        $controller_pkg->config(namespace=>$destination_name);
    }

    return $controller_pkg;
}

=method C<_generate_register_action_modifier>

  my $modifier = $self->_generate_register_action_modifier(
                   $appname,$destination,
                   $controller_pkg,
                   $config,$route);

Returns a coderef to be installed as an C<after> method modifier to
the C<register_actions> method. The coderef will register each action
with the Catalyst dispatcher. Each action will have the attribute
C<MessageTarget>, see L<Catalyst::Controller::JMS>.

Each action's code is obtained by calling L</_wrap_code>.

=cut

sub _generate_register_action_modifier {
    my ($self,$appname,$destination_name,$controller_pkg,$config,$route) = @_;

    return sub {
        my ($self_controller,$c) = @_;

        for my $type (keys %$route) {

            my $coderef = $self->_wrap_code(
                $c,
                $route->{$type},
            );
            my $action = $self_controller->create_action(
                name => $type,
                code => $coderef,
                reverse => "$destination_name/$type",
                namespace => $destination_name,
                class => $controller_pkg,
                attributes => {
                    MessageTarget => [$type],
                },
            );
            $c->dispatcher->register($c,$action);
        }
    }
}

=begin Pod::Coverage

routes

expand_modules

=end Pod::Coverage

=cut

1;
