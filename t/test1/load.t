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
               'Test1::Controller::base_url' => all(
                   isa('Catalyst::Controller'),
                   methods(
                       action_namespace => 'base_url',
                       path_prefix => 'base_url',
                   ),
               ),
               'Test1::Foo::One' => ignore(),
           },
           'components loaded'
);

done_testing();
