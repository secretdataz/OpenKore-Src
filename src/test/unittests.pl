#!/usr/bin/env perl
use strict;
use FindBin qw($RealBin);
use lib "$RealBin";
use lib "$RealBin/..";
use lib "$RealBin/../deps";

use List::MoreUtils;

use Test::More qw(no_plan);
my @tests = qw(CallbackListTest ObjectListTest ActorListTest WhirlpoolTest RijndaelTest
	SetTest SkillTest InventoryListTest
	ItemsTest
	TaskManagerTest TaskWithSubtaskTest TaskChainedTest
	PluginsHookTest
	FileParsersTest
	NetworkTest
	FieldTest
	eAthenaTest
);
if ($^O eq 'MSWin32') {
	push @tests, qw(HttpReaderTest);
}

@tests = @ARGV if (@ARGV);
foreach my $module (@tests) {
	$module =~ s/\.pm$//;
	eval {
		require "${module}.pm";
	};
	if ($@) {
		$@ =~ s/\(\@INC contains: .*?\) //s;
		print STDERR "Cannot load unit test $module:\n$@\n";
		exit 1;
	}
	$module->start;
}
