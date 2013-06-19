#!perl
use warnings;
use Test::Most;
use Test::Fatal;
use Data::Printer;
use HTTP::Request::Common;
use lib 't/lib';

BEGIN { $ENV{CATALYST_CONFIG} = 't/lib/test1.conf' }
use Catalyst::Test 'Test1';

# let's get all URLs from the controllers, to make sure they got
# created properly, 2 controllers for a single Foo, because of the
# configuration
my @destinations =
    map { '/'.$_ }
    map { Test1->controller($_)->action_namespace }
    Test1->controllers;

my $foo_one = Test1->component('Test1::Foo::One');

sub run_test {
    my ($url) = @_;

    $foo_one->calls([]);

    my $res = request POST "$url/my_action",
        'My-Header' => 'my value',
        'Content-type' => 'text/plain',
        'Content-length' => 6,
        Content => 'a body';

    ok($res->is_success, 'the request works')
        or note p $res;

    cmp_deeply($foo_one->calls,
               [
                   [
                       all(isa('HTTP::Headers'),
                           methods([header => 'My-Header'] => 'my value'),
                       ),
                       'a body',
                   ],
               ],
               'request received and action run')
        or note p $foo_one->calls;
}

subtest 'request on a configured destination' => sub {
    run_test('/url/1');
};

subtest 'request on the other configured destination' => sub {
    run_test('/url/2');
};

done_testing();
