package CatalystX::ControllerBuilder;
use Moose::Role;
use namespace::autoclean;
use Class::Load ();
use Catalyst::Utils ();

# ABSTRACT: role for components providing Catalyst actions

=head1 SYNOPSIS

  package MyApp::Base::Stuff;
  use Moose;
  extends 'Catalyst::Component';
  with 'CatalystX::ControllerBuilder';

  sub _kind_name {'Stuff'}
  sub _wrap_code {
    my ($self,$c,$url_prefix,$action_name,$route) = @_;
    my $code = $route->{code};
    my $extra_config = $route->{extra_config};
    return sub {
      my ($controller,$ctx) = @_;
      $self->$code($ctx->req,$extra_config);
    }
  }

Then:

  package MyApp::Stuff::One;
  use Moose;
  extends 'MyApp::Base::Stuff';

  sub routes {
    return {
      '/some/url' => {
        action_name => {
          code => \&my_action_method,
          extra_config => $whatever,
        },
        ...
      },
      ...
    }
  }

  sub my_action_method {
    my ($self,$request) = @_;

    # do something
  }

Also, remember to tell L<Catalyst> to load your C<Stuff> components:

  <setup_components>
   search_extra [ ::Stuff ]
  </setup_components>

=head1 DESCRIPTION

This role is to be used to define base classes for your Catalyst
applications. It's I<not> to be consumed directly by application
components. Classes inheriting from those base classes will, when
loaded, create controllers and register their actions inside them.

=head2 Routing

Subclasses of your component base specify which URLs they are
interested in, by writing a C<routes> sub, see the synopsis for an
example.

They can specify as many URLs and action names as they want / need,
and they can re-use the C<code> values as many times as needed.

The main limitation is that you can't have two components using the
exact same URL / action name pair (even if they derive from different
base classes!). If you do, the results are undefined.

It is possible to alter the URL via configuration, like:

  <Stuff::One>
   <routes_map>
    logical_url  /the/actual/url
   </routes_map>
  </Stuff::One>

You can also do this:

  <Stuff::One>
   <routes_map>
    logical_url  /the/actual/url
    logical_url  /another/url
   </routes_map>
  </Stuff::One>

to get your class to respond to two different URLs without altering
the code.

=head2 The "code"

The hashref specified by each URL / action name pair will be passed to
the L</_wrap_code> function (that the consuming class has to provide),
and the coderef returned will be installed as the action to invoke for
that name under that URL.

The action, like all Catalyst actions, will be invoked passing:

=over 4

=item *

the controller instance (you should rarely need this)

=item *

the Catalyst application context

=back

You can do whatever you need in this coderef, but the synopsis gives a
generally useful idea.

=cut

sub routes {
    die "the 'routes' method needs to be implemented in class $_[0]\n"
}

has routes_map => (
    is => 'ro',
    isa => 'HashRef',
    default => sub { { } },
);

has enabled => (
    is => 'ro',
    isa => 'Bool',
    default => 1,
);

=head1 Required methods

=head2 C<_kind_name>

As in the synopsis, this should return a string that, in the names of
the classes deriving from the consuming class, separates the
"application name" from the "component name".

These names are mostly used to access the configuration.

=cut

requires '_kind_name';

=head2 C<_wrap_code>

This method is called with:

=over 4

=item *

the Catalyst application as passed to C<register_actions>

=item *

the URL

=item *

the action name

=item *

the value from the C<routes> corresponding to the URL and action name
slot (see L</Routing> above)

=back

The coderef returned will be invoked as a Catalyst action for each
matching request, which means it will get:

=over 4

=item *

the controller instance (you should rarely need this)

=item *

the Catalyst application context

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
correct configuration options. This is were L</_kind_name> is used.

=cut

sub _split_class_name {
    my ($self,$class_name) = @_;
    my $kind_name = $self->_kind_name;

    my ($appname,$basename) = ($class_name =~ m{^((?:\w|:)+)::\Q$kind_name\E::(.*)$});
    return ($appname,$basename);
}

around COMPONENT => sub {
    my ($orig,$class,$appclass,$config) = @_;

    my ($appname,$basename) = $class->_split_class_name($class);
    my $kind_name = $class->_kind_name;
    my $ext_config = $appclass->config->{"${kind_name}::${basename}"} || {};
    my $merged_config = Catalyst::Utils::merge_hashes($ext_config,$config);

    return $class->$orig($appclass,$merged_config);
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

    my ($appname,$basename) = $class->_split_class_name($class);

    my $pre_routes = $class->routes;

    return unless $self->enabled;

    my %routes;
    for my $url (keys %$pre_routes) {
        my $real_url = $self->routes_map->{$url}
            || $url;
        my $route = $pre_routes->{$url};
        if (ref($real_url) eq 'ARRAY') {
            @{$routes{$_}}{keys %$route} = values %$route
                for @$real_url;
        }
        else {
            @{$routes{$real_url}}{keys %$route} = values %$route;
        }
    }

    my @result;

    for my $url (keys %routes) {
        my $route = $routes{$url};

=pod

We generate a controller package for each destination, by calling
L</_generate_controller_package>, and we add an C<after> method
modifier to its C<register_actions> method inherited from
C<Catalyst::Controller>, to create the actions for each message
type. The modifier is generated by calling
L</_generate_register_action_modifier>.

=cut

        my $controller_pkg = $self->_generate_controller_package(
            $appname,$url,$config,$route,
        );

        $controller_pkg->meta->add_after_method_modifier(
            'register_actions' =>
                $self->_generate_register_action_modifier(
                    $appname,$url,
                    $controller_pkg,
                    $config,$route,
                ),
        );

        push @result,$controller_pkg;
    }

    #$_->meta->make_immutable for @result;

    return @result;
}

=head2 C<_generate_controller_package>

  my $pkg = $self->_generate_controller_package(
                $appname,$url,
                $config,$route);

Generates a controller package, inheriting from whatever
L</_controller_base_classes> returns, called
C<${appname}::Controller::${url}>. Any roles returned by
L</_controller_roles> are applied to the controller.

Inside the controller, we set the C<namespace> config slot to the
C<$url>.

=cut

sub _generate_controller_package {
    my ($self,$appname,$url,$config,$route) = @_;

    $url =~ s{^/+}{};
    my $pkg_safe_url = $url;
    $pkg_safe_url =~ s{\W+}{_}g;

    my $controller_pkg = "${appname}::Controller::${pkg_safe_url}";

    our $VERSION; # get the global, set by Dist::Zilla

    if (!Class::Load::is_class_loaded($controller_pkg)) {

        my @superclasses = $self->_controller_base_classes;
        my @roles = $self->_controller_roles;
        Class::Load::load_class($_) for @superclasses,@roles;

        my $meta = Moose::Meta::Class->create(
            $controller_pkg => (
                version => $VERSION,
                superclasses => \@superclasses,
            )
        );
        for my $role (@roles) {
            my $metarole = Moose::Meta::Role->initialize($role);
            next unless $metarole;
            $metarole->apply($meta);
        }
        $controller_pkg->config(namespace=>$url);
    }

    return $controller_pkg;
}

=head2 C<_controller_base_classes>

List (not arrayref!) of class names that the controllers generated by
L</_generate_controller_package> should inherit from. Defaults to
C<'Catalyst::Controller'>.

=cut

sub _controller_base_classes { 'Catalyst::Controller' }

=head2 C<_controller_roles>

List (not arrayref!) of role names that should be applied to the
controllers created by L</_generate_controller_package>. Defaults to
the empty list.

=cut

sub _controller_roles { }

=head2 C<_generate_register_action_modifier>

  my $modifier = $self->_generate_register_action_modifier(
                   $appname,$url,
                   $controller_pkg,
                   $config,$route);

Returns a coderef to be installed as an C<after> method modifier to
the C<register_actions> method. The coderef will register each action
with the Catalyst dispatcher. You can pass additional parameters to
the controller's C<create_action> method by overriding
L</_action_extra_params>.

Each action's code is obtained by calling L</_wrap_code>.

=cut

sub _generate_register_action_modifier {
    my ($self,$appname,$url,$controller_pkg,$config,$route) = @_;

    $url =~ s{^/+}{};
    return sub {
        my ($self_controller,$c) = @_;

        for my $action_name (keys %$route) {

            my $coderef = $self->_wrap_code(
                $c,$url,
                $action_name,$route->{$action_name},
            );
            my $action = $self_controller->create_action(
                $self->_action_extra_params(
                    $c,$url,
                    $action_name,$route->{$action_name},
                ),
                name => $action_name,
                code => $coderef,
                reverse => "$url/$action_name",
                namespace => $url,
                class => $controller_pkg,
            );
            $c->dispatcher->register($c,$action);
        }
    }
}

=head2 C<_action_extra_params>

  my %extra_params = $self->_action_extra_params(
                      $c,$url,
                      $action_name,$route->{$action_name},
                     );

You can override this method to provide additional arguments for the
C<create_action> call inside
C</_generate_register_action_modifier>. For example you could return:

  attributes => { MySpecialAttr => [ 'foo' ] }

to set that attribute for all generated actions.

=cut

sub _action_extra_params {}

=begin Pod::Coverage

routes

expand_modules

=end Pod::Coverage

=cut

1;
