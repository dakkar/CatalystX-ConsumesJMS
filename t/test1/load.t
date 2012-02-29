#!perl
use strict;
use warnings;
use Test::Most;
use lib 't/lib';
use ok 'Test1';

my $components=Test1->components;
cmp_deeply($components,
           {
               Test1 => ignore(),
               'Test1::Controller::input_queue' => all(
                   isa('Catalyst::Controller::JMS'),
                   methods(
                       action_namespace => 'input_queue',
                       path_prefix => 'input_queue',
                   ),
               ),
               'Test1::Foo::One' => ignore(),
           },
           'components loaded'
);

done_testing();
