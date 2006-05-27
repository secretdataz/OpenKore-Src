#!/usr/bin/env perl
use strict;
no strict 'refs';
use FindBin qw($RealBin);
use lib "$RealBin/..";

use Test::More qw(no_plan);
my @tests = qw(CallbackListTest ObjectListTest ActorListTest);
if ($^O eq 'MSWin32') {
	push @tests, qw(HttpReaderTest);
}

@tests = @ARGV if (@ARGV);
foreach my $module (@tests) {
	eval {
		require "${module}.pm";
	};
	if ($@) {
		$@ =~ s/\(\@INC contains: .*?\) //s;
		print STDERR "Cannot load unit test $module:\n$@\n";
		exit 1;
	}
	my $start = "${module}::start";
	$start->();
}
