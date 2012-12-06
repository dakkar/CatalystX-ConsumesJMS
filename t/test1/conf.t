#!perl
use warnings;
use Test::Most;
use Test::Fatal;
use Test::Plack::Handler::Stomp;
use Net::Stomp::Frame;
use Data::Printer;
use lib 't/lib';

$ENV{CATALYST_CONFIG} = 't/lib/test1.conf';
require Test1;

# let's get the destinations from the controllers, to make sure they
# got created properly, 2 controllers for a single Foo, because of the
# configuration
my @destinations =
    map { '/'.$_ }
    grep { m{^(queue|topic)}x }
    map { Test1->controller($_)->action_namespace }
    Test1->controllers;

my $t = Test::Plack::Handler::Stomp->new();
$t->set_arg(
    subscriptions => [
        map { +{ destination => $_ } } @destinations,
    ],
);
$t->clear_frames_to_receive;
$t->clear_sent_frames;

my $app;
if (Test1->can('psgi_app')) {
    $app = Test1->psgi_app;
}
else {
    Test1->setup_engine('PSGI');
    $app = sub { Test1->run(@_) };
}
my $consumer = Test1->component('Test1::Foo::One');

sub run_test {
    my ($dest) = @_;

    my $code = time();

    $consumer->messages([]);

    $t->queue_frame_to_receive(Net::Stomp::Frame->new({
        command => 'MESSAGE',
        headers => {
            destination => $dest,
            'content-type' => 'json',
            type => 'my_type',
            'message-id' => $code,
        },
        body => qq{{"foo":"$dest"}},
    }));

    my $e = exception { $t->handler->run($app) };
    is($e,undef, 'consuming the message lives')
        or note p $e;

    cmp_deeply($consumer->messages,
               [
                   [
                       isa('HTTP::Headers'),
                       { foo => $dest },
                   ],
               ],
               'message consumed & logged')
        or note p $consumer->messages;

    cmp_deeply($t->frames_sent,
               [
                   all(
                       isa('Net::Stomp::Frame'),
                       methods(
                           command=>'SEND',
                           body=>'{"no":"thing"}',
                           headers => {
                               destination => '/remote-temp-queue/reply-address',
                           },
                       )
                   ),
                   all(
                       isa('Net::Stomp::Frame'),
                       methods(
                           command=>'ACK',
                           body=>undef,
                           headers => {
                               'message-id' => $code,
                           },
                       )
                   ),
               ],
               'reply & ack sent');
    $t->clear_sent_frames;
}

subtest 'message on a configured destination' => sub {
    run_test('/queue/input1');
};

subtest 'message on the other configured destination' => sub {
    run_test('/queue/input2');
};

done_testing();
