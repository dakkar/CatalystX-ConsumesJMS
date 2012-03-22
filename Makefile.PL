
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "role for components providing Catalyst actions consuming messages",
  "AUTHOR" => "Gianni Ceccarelli <gianni.ceccarelli\@net-a-porter.com>",
  "BUILD_REQUIRES" => {
    "Catalyst" => 0,
    "Catalyst::Component" => 0,
    "Catalyst::Controller::JMS" => 0,
    "Data::Printer" => 0,
    "Moose" => 0,
    "MooseX::MethodAttributes::Role" => 0,
    "Net::Stomp::Frame" => 0,
    "Test::Fatal" => 0,
    "Test::More" => 0,
    "Test::Most" => 0,
    "Test::Plack::Handler::Stomp" => 0,
    "ok" => 0,
    "strict" => 0,
    "warnings" => 0
  },
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "CatalystX-ConsumesJMS",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "CatalystX::ConsumesJMS",
  "PREREQ_PM" => {
    "Catalyst::Controller::JMS" => 0,
    "Class::Load" => 0,
    "Moose::Role" => 0,
    "namespace::autoclean" => 0
  },
  "VERSION" => "0.1_04",
  "test" => {
    "TESTS" => "t/*.t t/test1/*.t t/test2/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



