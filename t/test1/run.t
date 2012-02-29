#!perl
use warnings;
use Test::Most;
use Test::Fatal;
use Test::Plack::Handler::Stomp;
use Net::Stomp::Frame;
use Data::Printer;
use lib 't/lib';
use Test1;

my $t = Test::Plack::Handler::Stomp->new();
$t->set_arg(
    subscriptions => [
        { destination => '/queue/input_queue',
          path_info => '/input_queue', },
    ],
);
$t->clear_frames_to_receive;
$t->queue_frame_to_receive(Net::Stomp::Frame->new({
    command => 'MESSAGE',
    headers => {
        destination => '/queue/input_queue',
        subscription => 0,
        type => 'my_type',
        'message-id' => 356,
    },
    body => '{"foo":"bar"}',
}));

my $app = Test1->psgi_app;
my $consumer = Test1->component('Test1::Foo::One');

my $e = exception { $t->handler->run($app) };
is($e,undef, 'consuming the message lives')
    or note p $e;

cmp_deeply($consumer->messages,
           [
               [
                   isa('HTTP::Headers'),
                   { foo => 'bar' },
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
                           'message-id' => 356,
                       },
                   )
               ),
           ],
           'relpy & ack sent');

done_testing();
