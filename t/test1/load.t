#!perl
use strict;
use warnings;
use Test::Most;
use Data::Printer;
use lib 't/lib';
use ok 'Test1';

my $components=Test1->components;
cmp_deeply($components,
           {
               Test1 => ignore(),
               'Test1::Controller::input_queue' => all(
                   isa('Catalyst::Controller::JMS'),
                   methods(
                       action_namespace => 'Test1',
                       path_prefix => 'Test1',
                   ),
               ),
               'Test1::Foo::One' => ignore(),
           },
           'components loaded'
);

done_testing();
