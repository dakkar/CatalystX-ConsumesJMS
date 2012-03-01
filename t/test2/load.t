#!perl
use strict;
use warnings;
use Test::Most;
use lib 't/lib';
use ok 'Test2';

my $components=Test2->components;
cmp_deeply($components,
           {
               Test2 => ignore(),
               'Test2::Controller::input_queue' => all(
                   isa('Catalyst::Controller::JMS'),
                   methods(
                       action_namespace => 'input_queue',
                       path_prefix => 'input_queue',
                   ),
               ),
               'Test2::Foo::One' => ignore(),
           },
           'components loaded'
);

done_testing();
