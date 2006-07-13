#########################################################################
#  OpenKore - Commandline
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#
#  $Revision$
#  $Id$
#
#########################################################################
##
# MODULE DESCRIPTION: Commandline input processing
#
# This module processes commandline input.

package Commands;

use strict;
use warnings;
no warnings qw(redefine uninitialized);
use Time::HiRes qw(time);
use encoding 'utf8';
use Translation;

use Globals;
use Log qw(message debug error warning);
use Network::Send;
use Settings;
use Plugins;
use Skills;
use Utils;
use Misc;
use AI;
use Match;


our %handlers;
our %completions;

undef %handlers;
undef %completions;

our %customCommands;


# use SelfLoader; 1;
# __DATA__

sub initHandlers {
	%handlers = (
	a                  => \&cmdAttack,
	ai                 => \&cmdAI,
	aiv                => \&cmdAIv,
	al                 => \&cmdShopInfoSelf,
	arrowcraft         => \&cmdArrowCraft,
	as                 => \&cmdAttackStop,
	autobuy            => \&cmdAutoBuy,
	autosell           => \&cmdAutoSell,
	autostorage        => \&cmdAutoStorage,
	auth               => \&cmdAuthorize,
	bangbang           => \&cmdBangBang,
	bingbing           => \&cmdBingBing,
	buy                => \&cmdBuy,
	c                  => \&cmdChat,
	card               => \&cmdCard,
	cart               => \&cmdCart,
	chat               => \&cmdChatRoom,
	chist              => \&cmdChist,
	cil                => \&cmdItemLogClear,
	cl                 => \&cmdChatLogClear,
	closeshop          => \&cmdCloseShop,
	conf               => \&cmdConf,
	damage             => \&cmdDamage,
	deal               => \&cmdDeal,
	debug              => \&cmdDebug,
	dl                 => \&cmdDealList,
	doridori           => \&cmdDoriDori,
	drop               => \&cmdDrop,
	dump               => \&cmdDump,
	dumpnow            => \&cmdDumpNow,
	e                  => \&cmdEmotion,
	eq                 => \&cmdEquip,
	eval               => \&cmdEval,
	exp                => \&cmdExp,
	falcon             => \&cmdFalcon,
	follow             => \&cmdFollow,
	friend             => \&cmdFriend,
	homun              => \&cmdHomunculus,
	g                  => \&cmdGuildChat,
	getplayerinfo      => \&cmdGetPlayerInfo,
	guild              => \&cmdGuild,
	help               => \&cmdHelp,
	i                  => \&cmdInventory,
	identify           => \&cmdIdentify,
	ignore             => \&cmdIgnore,
	ihist              => \&cmdIhist,
	il                 => \&cmdItemList,
	im                 => \&cmdUseItemOnMonster,
	ip                 => \&cmdUseItemOnPlayer,
	is                 => \&cmdUseItemOnSelf,
	kill               => \&cmdKill,
	look               => \&cmdLook,
	lookp              => \&cmdLookPlayer,
	memo               => \&cmdMemo,
	ml                 => \&cmdMonsterList,
	move               => \&cmdMove,
	nl                 => \&cmdNPCList,
	openshop           => \&cmdOpenShop,
	p                  => \&cmdPartyChat,
	party              => \&cmdParty,
	pecopeco           => \&cmdPecopeco,  
	#pet               => \&cmdPet,
	petl               => \&cmdPetList,
	pl                 => \&cmdPlayerList,
	plugin             => \&cmdPlugin,
	pm                 => \&cmdPrivateMessage,
	pml                => \&cmdPMList,
	portals            => \&cmdPortalList,
	quit               => \&cmdQuit,
	rc                 => \&cmdReloadCode,
	reload             => \&cmdReload,
	relog              => \&cmdRelog,
	repair             => \&cmdRepair,
	respawn            => \&cmdRespawn,
	s                  => \&cmdStatus,
	sell               => \&cmdSell,
	send               => \&cmdSendRaw,
	sit                => \&cmdSit,
	skills             => \&cmdSkills,
	spells             => \&cmdSpells,
	storage            => \&cmdStorage,
	store              => \&cmdStore,
	sl                 => \&cmdUseSkill,
	sm                 => \&cmdUseSkill,
	sp                 => \&cmdPlayerSkill,
	ss                 => \&cmdUseSkill,
	ssp                => \&cmdUseSkill,
	st                 => \&cmdStats,
	stand              => \&cmdStand,
	stat_add           => \&cmdStatAdd,
	switchconf         => \&cmdSwitchConf,
	take               => \&cmdTake,
	talk               => \&cmdTalk,
	talknpc            => \&cmdTalkNPC,
	tank               => \&cmdTank,
	tele               => \&cmdTeleport,
	testshop           => \&cmdTestShop,
	timeout            => \&cmdTimeout,
	uneq               => \&cmdUnequip,
	vender             => \&cmdVender,
	verbose            => \&cmdVerbose,
	version            => \&cmdVersion,
	vl                 => \&cmdVenderList,
	warp               => \&cmdWarp,
	weight             => \&cmdWeight,
	where              => \&cmdWhere,
	who                => \&cmdWho,
	whoami             => \&cmdWhoAmI,

	north              => \&cmdManualMove,
	south              => \&cmdManualMove,
	east               => \&cmdManualMove,
	west               => \&cmdManualMove,
	northeast          => \&cmdManualMove,
	northwest          => \&cmdManualMove,
	southeast          => \&cmdManualMove,
	southwest          => \&cmdManualMove,
	);
}

sub initCompletions {
	%completions = (
	sp		=> \&cmdPlayerSkill,
	);
}

##
# Commands::run(input)
# input: a command.
#
# Processes $input. See also <a href="http://openkore.sourceforge.net/docs.php">the user documentation</a>
# for a list of commands.
#
# Example:
# # Same effect as typing 's' in the console. Displays character status
# Commands::run("s");
sub run {
	my $input = shift;
	my ($switch, $args) = split(/ +/, $input, 2);
	my $handler;

	initHandlers() if (!%handlers);

	# Resolve command aliases
	if (my $alias = $config{"alias_$switch"}) {
		$input = $alias;
		$input .= " $args" if defined $args;
		($switch, $args) = split(/ +/, $input, 2);
	}

	$handler = $customCommands{$switch}{callback} if ($customCommands{$switch});
	$handler = $handlers{$switch} if (!$handler && $handlers{$switch});

	if ($handler) {
		my %params;

		$params{switch} = $switch;
		$params{args} = $args;
		Plugins::callHook("Commands::run/pre", \%params);
		$handler->($switch, $args);
		Plugins::callHook("Commands::run/post", \%params);
		return 1;

	} else {
		my %params = ( switch => $switch, input => $input );
		Plugins::callHook('Command_post', \%params);
		if (!$params{return}) {
			error TF("Unknown command '%s'. Please read the documentation for a list of commands.\n", $switch);
		} else {
			return $params{return}
		}
	}
}


##
# Commands::register([name, description, callback]...)
# Returns: an ID for use with Commands::unregister()
#
# Register new commands.
#
# Example:
# my $ID = Commands::register(
#     ["my_command", "My custom command's description", \&my_callback],
#     ["another_command", "Yet another command description", \&another_callback]
# );
# Commands::unregister($ID);
sub register {
	my @result;

	foreach my $cmd (@_) {
		my $name = $cmd->[0];
		my %item = (
			desc => $cmd->[1],
			callback => $cmd->[2]
		);
		$customCommands{$name} = \%item;
		push @result, $name;
	}
	return \@result;
}


##
# Commands::unregister(ID)
# ID: an ID returned by Commands::register()
#
# Unregisters a registered command.
sub unregister {
	my $ID = shift;

	foreach my $name (@{$ID}) {
		delete $customCommands{$name};
	}
}


sub complete {
	my $input = shift;
	my ($switch, $args) = split(/ +/, $input, 2);

	return if ($input eq '');
	initCompletions() if (!%completions);

	# Resolve command aliases
	if (my $alias = $config{"alias_$switch"}) {
		$input = $alias;
		$input .= " $args" if defined $args;
		($switch, $args) = split(/ +/, $input, 2);
	}

	my $completor;
	if ($completions{$switch}) {
		$completor = $completions{$switch};
	} else {
		$completor = \&defaultCompletor;
	}

	my ($last_arg_pos, $matches) = $completor->($switch, $input, 'c');
	if (@{$matches} == 1) {
		my $arg = $matches->[0];
		$arg = "\"$arg\"" if ($arg =~ / /);
		my $new = substr($input, 0, $last_arg_pos) . $arg;
		if (length($new) > length($input)) {
			return "$new ";
		} elsif (length($new) == length($input)) {
			return "$input ";
		}

	} elsif (@{$matches} > 1) {
		$interface->writeOutput("message", "\n" . join("\t", @{$matches}) . "\n", "info");

		## Find largest common prefix

		# Find item with smallest length
		my $smallest;
		foreach (@{$matches}) {
			if (!defined $smallest || length($_) < $smallest) {
				$smallest = length($_);
			}
		}

		my $commonStr;
		for (my $len = $smallest; $len >= 0; $len--) {
			my $first = lc(substr($matches->[0], 0, $len));
			my $common = 1;
			foreach (@{$matches}) {
				if ($first ne lc(substr($_, 0, $len))) {
					$common = 0;
					last;
				}
			}
			if ($common) {
				$commonStr = $first;
				last;
			}
		}

		my $new = substr($input, 0, $last_arg_pos) . $commonStr;
		return $new if (length($new) > length($input));
	}
	return $input;
}


##################################


sub completePlayerName {
	my $arg = quotemeta shift;
	my @matches;
	foreach (@playersID) {
		next if (!$_);
		if ($players{$_}{name} =~ /^$arg/i) {
			push @matches, $players{$_}{name};
		}
	}
	return @matches;
}

sub defaultCompletor {
	my $switch = shift;
	my $last_arg_pos;
	my @args = parseArgs(shift, undef, undef, \$last_arg_pos);
	my @matches;

	my $arg = $args[$#args];
	@matches = completePlayerName($arg);
	@matches = Skills::complete($arg) if (!@matches);
	return ($last_arg_pos, \@matches);
}


##################################


sub cmdAI {
	my (undef, $args) = @_;
	$args =~ s/ .*//;

	# Clear AI
	if ($args eq 'clear') {
		AI::clear;
		delete $ai_v{temp};
		undef $char->{dead};
		message T("AI sequences cleared\n"), "success";

	} elsif ($args eq 'print') {
		# Display detailed info about current AI sequence
		message T("------ AI Sequence ---------------------\n"), "list";
		my $index = 0;
		foreach (@ai_seq) {
			message("$index: $_ " . dumpHash(\%{$ai_seq_args[$index]}) . "\n\n", "list");
			$index++;
		}

		message T("------ AI Sequences --------------------\n"), "list";

	} elsif ($args eq 'ai_v') {
		message dumpHash(\%ai_v) . "\n", "list";

	} elsif ($args eq 'on' || $args eq 'auto') {
		# Set AI to auto mode
		if ($AI == 2) {
			message T("AI is already set to auto mode\n"), "success";
		} else {
			$AI = 2;
			undef $AI_forcedOff;
			message T("AI set to auto mode\n"), "success";
		}
	} elsif ($args eq 'manual') {
		# Set AI to manual mode
		if ($AI == 1) {
			message T("AI is already set to manual mode\n"), "success";
		} else {
			$AI = 1;
			$AI_forcedOff = 1;
			message T("AI set to manual mode\n"), "success";
		}
	} elsif ($args eq 'off') {
		# Turn AI off
		if ($AI) {
			undef $AI;
			$AI_forcedOff = 1;
			message T("AI turned off\n"), "success";
		} else {
			message T("AI is already off\n"), "success";
		}

	} elsif ($args eq '') {
		# Toggle AI
		if ($AI == 2) {
			undef $AI;
			$AI_forcedOff = 1;
			message T("AI turned off\n"), "success";
		} elsif (!$AI) {
			$AI = 1;
			$AI_forcedOff = 1;
			message T("AI set to manual mode\n"), "success";
		} elsif ($AI == 1) {
			$AI = 2;
			undef $AI_forcedOff;
			message T("AI set to auto mode\n"), "success";
		}

	} else {
		error T("Syntax Error in function 'ai' (AI Commands)\n" .
			"Usage: ai [ clear | print | ai_v | auto | manual | off ]\n");
	}
}

sub cmdAIv {
	# Display current AI sequences
	my $on;
	if (!$AI) {
		message TF("ai_seq (off) = %s\n", "@ai_seq"), "list";
	} elsif ($AI == 1) {
		message TF("ai_seq (manual) = %s\n", "@ai_seq"), "list";
	} elsif ($AI == 2) {
		message TF("ai_seq (auto) = %s\n", "@ai_seq"), "list";
	}
	message T("solution\n"), "list" if (AI::args->{'solution'});
}

sub cmdArrowCraft {
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^(\w+)/;
	my ($arg2) = $args =~ /^\w+ (\d+)/;

	#print "-$arg1-\n";
	if ($arg1 eq "") {
		if (@arrowCraftID) {
			message T("----------------- Item To Craft -----------------\n"), "info";
			for (my $i = 0; $i < @arrowCraftID; $i++) {
				next if ($arrowCraftID[$i] eq "");
				message(swrite(
					"@<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<",
					[$i, $char->{inventory}[$arrowCraftID[$i]]{name}]),"list");

			}
			message("-------------------------------------------------\n","list")
		} else {
			error T("Error in function 'arrowcraft' (Create Arrows)\n" .
			 	"Type 'arrowcraft use' to get list.\n");
		}
	} elsif ($arg1 eq "use") {
		if (defined binFind(\@skillsID, 'AC_MAKINGARROW')) {
			main::ai_skillUse('AC_MAKINGARROW', 1, 0, 0, $accountID);
		} else {
			error T("Error in function 'arrowcraft' (Create Arrows)\n" . 
				"You don't have Arrow Making Skill.\n");
		}
	} elsif ($arg1 eq "forceuse") {
		if ($char->{inventory}[$arg2] && %{$char->{inventory}[$arg2]}) {
			sendArrowCraft($net, $char->{inventory}[$arg2]{nameID});
		} else {
			error TF("Error in function 'arrowcraft forceuse #' (Create Arrows)\n" . 
				"You don't have item %s in your inventory.\n", $arg2);
		}
	} else {
		if ($arrowCraftID[$arg1] ne "") {
			sendArrowCraft($net, $char->{inventory}[$arrowCraftID[$arg1]]{nameID});
		} else {
			error T("Error in function 'arrowcraft' (Create Arrows)\n" .
				"Usage: arrowcraft [<identify #>]\n" .
				"Type 'arrowcraft use' to get list.\n");
		}
	}
}

sub cmdAttack {
	my (undef, $arg1) = @_;
	if ($arg1 =~ /^\d+$/) {
		if ($monstersID[$arg1] eq "") {
			error TF("Error in function 'a' (Attack Monster)\n" . 
				"Monster %s does not exist.\n", $arg1);
		} else {
			main::attack($monstersID[$arg1]);
		}
	} elsif ($arg1 eq "no") {
		configModify("attackAuto", 1);

	} elsif ($arg1 eq "yes") {
		configModify("attackAuto", 2);

	} else {
		error T("Syntax Error in function 'a' (Attack Monster)\n" . 
			"Usage: attack <monster # | no | yes >\n");
	}
}

sub cmdAttackStop {
	my $index = AI::findAction("attack");
	if ($index ne "") {
		my $args = AI::args($index);
		my $monster = Actor::get($args->{ID});
		if ($monster) {
			$monster->{ignore} = 1;
			stopAttack();
			message TF("Stopped attacking %s (%s)\n", 
				$monster->{name}, $monster->{binID}), "success";
			AI::clear("attack");
		}
	}
}

sub cmdAuthorize {
	my (undef, $args) = @_;
	my ($arg1, $arg2) = $args =~ /^([\s\S]*) ([\s\S]*?)$/;
	if ($arg1 eq "" || ($arg2 ne "1" && $arg2 ne "0")) {
		error T("Syntax Error in function 'auth' (Overall Authorize)\n" . 
			"Usage: auth <username> <flag>\n");
	} else {
		auth($arg1, $arg2);
	}
}

sub cmdAutoBuy {
	message T("Initiating auto-buy.\n");
	AI::queue("buyAuto");
}

sub cmdAutoSell {
	message T("Initiating auto-sell.\n");
	AI::queue("sellAuto");
}

sub cmdAutoStorage {
	message T("Initiating auto-storage.\n");
	AI::queue("storageAuto");
}

sub cmdBangBang {
	my $bodydir = $char->{look}{body} - 1;
	$bodydir = 7 if ($bodydir == -1);
	sendLook($net, $bodydir, $char->{look}{head});
}

sub cmdBingBing {
	my $bodydir = ($char->{look}{body} + 1) % 8;
	sendLook($net, $bodydir, $char->{look}{head});
}

sub cmdBuy {
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^(\d+)/;
	my ($arg2) = $args =~ /^\d+ (\d+)$/;
	if ($arg1 eq "") {
		error T("Syntax Error in function 'buy' (Buy Store Item)\n" . 
			"Usage: buy <item #> [<amount>]\n");
	} elsif ($storeList[$arg1] eq "") {
		error TF("Error in function 'buy' (Buy Store Item)\n" . 
			"Store Item %s does not exist.\n", $arg1);
	} else {
		if ($arg2 <= 0) {
			$arg2 = 1;
		}
		sendBuy($net, $storeList[$arg1]{'nameID'}, $arg2);
	}
}

sub cmdCard {
	my (undef, $input) = @_;
	my ($arg1) = $input =~ /^(\w+)/;
	my ($arg2) = $input =~ /^\w+ (\d+)/;
	my ($arg3) = $input =~ /^\w+ \d+ (\d+)/;

	if ($arg1 eq "mergecancel") {
		if ($cardMergeIndex ne "") {
			undef $cardMergeIndex;
			sendCardMerge($net, -1, -1);
			message T("Cancelling card merge.\n");
		} else {
			error T("Error in function 'card mergecancel' (Cancel a card merge request)\n" . 
				"You are not currently in a card merge session.\n");
		}
	} elsif ($arg1 eq "mergelist") {
		# FIXME: if your items change order or are used, this list will be wrong
		if (@cardMergeItemsID) {
			my $msg;
			$msg .= T("-----Card Merge Candidates-----\n");
			foreach my $card (@cardMergeItemsID) {
				next if $card eq "" || !$char->{inventory}[$card] ||
					!%{$char->{inventory}[$card]};
				$msg .= swrite(
					"@<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<",
					[$card, $char->{inventory}[$card]]);
			}
			$msg .= "-------------------------------\n";
			message $msg, "list";
		} else {
			error T("Error in function 'card mergelist' (List availible card merge items)\n" . 
				"You are not currently in a card merge session.\n");
		}
	} elsif ($arg1 eq "merge") {
		if ($arg2 =~ /^\d+$/) {
			my $found = binFind(\@cardMergeItemsID, $arg2);
			if (defined $found) {
				sendCardMerge($net, $char->{inventory}[$cardMergeIndex]{index}, $char->{inventory}[$arg2]{index});
			} else {
				if ($cardMergeIndex ne "") {
					error TF("Error in function 'card merge' (Finalize card merging onto item)\n" . 
						"There is no item %s in the card mergelist.\n", $arg2);
				} else {
					error T("Error in function 'card merge' (Finalize card merging onto item)\n" . 
						"You are not currently in a card merge session.\n");
				}
			}
		} else {
			error T("Syntax Error in function 'card merge' (Finalize card merging onto item)\n" .
				"Usage: card merge <item number>\n" . 
				"<item number> - Merge item number. Type 'card mergelist' to get number.\n");
		}
	} elsif ($arg1 eq "use") {
		if ($arg2 =~ /^\d+$/) {
			if ($char->{inventory}[$arg2] && %{$char->{inventory}[$arg2]}) {
				$cardMergeIndex = $arg2;
				sendCardMergeRequest($net, $char->{inventory}[$cardMergeIndex]{index});
				message TF("Sending merge list request for %s...\n", 
					$char->{inventory}[$cardMergeIndex]{name});
			} else {
				error TF("Error in function 'card use' (Request list of items for merging with card)\n" . 
					"Card %s does not exist.\n", $arg2);
			}
		} else {
			error T("Syntax Error in function 'card use' (Request list of items for merging with card)\n" .
				"Usage: card use <item number>\n" .
				"<item number> - Card inventory number. Type 'i' to get number.\n");
		}
	} elsif ($arg1 eq "list") {
		my $msg;
		$msg .= T("-----------Card List-----------\n");
		for (my $i = 0; $i < @{$char->{inventory}}; $i++) {
			next if (!$char->{'inventory'}[$i] || !%{$char->{'inventory'}[$i]});
			if ($char->{inventory}[$i]{type} == 6) {
				$msg .= "$i $char->{inventory}[$i]{name} x $char->{inventory}[$i]{amount}\n";
			}
		}
		$msg .= "-------------------------------\n";
		message $msg, "list";
	} elsif ($arg1 eq "forceuse") {
		if (!$char->{inventory}[$arg2] || !%{$char->{inventory}[$arg2]}) {
			error TF("Error in function 'arrowcraft forceuse #' (Create Arrows)\n" .
				"You don't have item %s in your inventory.\n", $arg2);
		} elsif (!$char->{inventory}[$arg3] || !%{$char->{inventory}[$arg3]}) {
			error TF("Error in function 'arrowcraft forceuse #' (Create Arrows)\n" .
				"You don't have item %s in your inventory.\n"), $arg3;
		} else {
			sendCardMerge($net, $char->{inventory}[$arg2]{index}, $char->{inventory}[$arg3]{index});
		}
	} else {
		error T("Syntax Error in function 'card' (Card Compounding)\n" .
			"Usage: card <use|mergelist|mergecancel|merge>\n");
	}
}

sub cmdCart {
	my (undef, $input) = @_;
	my ($arg1, $arg2) = split(' ', $input, 2);

	if (!$cart{exists}) {
		error T("Error in function 'cart' (Cart Management)\n" .
			"You do not have a cart.\n");
		return;
		
	} elsif (!defined $cart{'inventory'}) {
		error T("Cart inventory is not available.\n");
		return;

	} elsif ($arg1 eq "") {
		my $msg = T("-------------Cart--------------\n" .
			"#  Name\n");
		for (my $i = 0; $i < @{$cart{'inventory'}}; $i++) {
			next if (!$cart{'inventory'}[$i] || !%{$cart{'inventory'}[$i]});
			my $display = "$cart{'inventory'}[$i]{'name'} x $cart{'inventory'}[$i]{'amount'}";
			$display .= T(" -- Not Identified") if !$cart{inventory}[$i]{identified};
			$msg .= sprintf("%-2d %-34s\n", $i, $display);
		}
		$msg .= TF("\nCapacity: %d/%d  Weight: %d/%d\n", 
			int($cart{'items'}), int($cart{'items_max'}), int($cart{'weight'}), int($cart{'weight_max'}));
		$msg .= "-------------------------------\n";
		message($msg, "list");

	} elsif ($arg1 eq "add") {
		cmdCart_add($arg2);

	} elsif ($arg1 eq "get") {
		cmdCart_get($arg2);

	} elsif ($arg1 eq "desc") {
		if (!($arg2 =~ /\d+/)) {
			error TF("Syntax Error in function 'cart desc' (Show Cart Item Description)\n" .
				"'%s' is not a valid cart item number.\n", $arg2);
		} elsif (!$cart{'inventory'}[$arg2]) {
			error TF("Error in function 'cart desc' (Show Cart Item Description)\n" .
				"Cart Item %s does not exist.\n", $arg2);
		} else {
			printItemDesc($cart{'inventory'}[$arg2]{'nameID'});
		}
		
	} elsif ($arg1 eq "release") {
		sendCompanionRelease();
		if ($conState == 5) {
			message T("Cart released.\n"), "success";
			$cart{exists} = 0;
		}
	
	} else {
		error TF("Error in function 'cart'\n" .
			"Command '%s' is not a known command.\n", $arg1);
	}
}

sub cmdCart_add {
	my ($name) = @_;

	if (!defined $name) {
		error T("Syntax Error in function 'cart add' (Add Item to Cart)\n" . 
			"Usage: cart add <item>\n");
		return;
	}

	my $amount;
	if ($name =~ /^(.*?) (\d+)$/) {
		$name = $1;
		$amount = $2;
	}

	my $item = Match::inventoryItem($name);

	if (!$item) {
		error TF("Error in function 'cart add' (Add Item to Cart)\n" .
			"Inventory Item %s does not exist.\n", $name);
		return;
	}

	if (!$amount || $amount > $item->{amount}) {
		$amount = $item->{amount};
	}
	sendCartAdd($item->{index}, $amount);
}

sub cmdCart_get {
	my ($name) = @_;

	if (!defined $name) {
		error T("Syntax Error in function 'cart get' (Get Item from Cart)\n" .
			"Usage: cart get <cart item>\n");
		return;
	}

	my $amount;
	if ($name =~ /^(.*?) (\d+)$/) {
		$name = $1;
		$amount = $2;
	}

	my $item = Match::cartItem($name);
	if (!$item) {
		error TF("Error in function 'cart get' (Get Item from Cart)\n" .
			"Cart Item %s does not exist.\n", $name);
		return;
	}

	if (!$amount || $amount > $item->{amount}) {
		$amount = $item->{amount};
	}
	sendCartGet($item->{index}, $amount);
}


sub cmdChat {
	my (undef, $arg1) = @_;
	if ($arg1 eq "") {
		error T("Syntax Error in function 'c' (Chat)\n" .
			"Usage: c <message>\n");
	} else {
		sendMessage($net, "c", $arg1);
	}
}

sub cmdChatLogClear {
	chatLog_clear();
	message T("Chat log cleared.\n"), "success";
}

sub cmdChatRoom {
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^(\w+)/;

	if ($arg1 eq "bestow") {
		my ($arg2) = $args =~ /^\w+ (\d+)/;

		if ($currentChatRoom eq "") {
			error T("Error in function 'chat bestow' (Bestow Admin in Chat)\n" .
				"You are not in a Chat Room.\n");
		} elsif ($arg2 eq "") {
			error T("Syntax Error in function 'chat bestow' (Bestow Admin in Chat)\n" .
				"Usage: chat bestow <user #>\n");
		} elsif ($currentChatRoomUsers[$arg2] eq "") {
			error TF("Error in function 'chat bestow' (Bestow Admin in Chat)\n" .
				"Chat Room User %s doesn't exist; type 'chat info' to see the list of users\n", $arg2);
		} else {
			sendChatRoomBestow($net, $currentChatRoomUsers[$arg2]);
		}

	} elsif ($arg1 eq "modify") {
		my ($title) = $args =~ /^\w+ \"([\s\S]*?)\"/;
		my ($users) = $args =~ /^\w+ \"[\s\S]*?\" (\d+)/;
		my ($public) = $args =~ /^\w+ \"[\s\S]*?\" \d+ (\d+)/;
		my ($password) = $args =~ /^\w+ \"[\s\S]*?\" \d+ \d+ ([\s\S]+)/;

		if ($title eq "") {
			error T("Syntax Error in function 'chatmod' (Modify Chat Room)\n" .
				"Usage: chat modify \"<title>\" [<limit #> <public flag> <password>]\n");
		} else {
			if ($users eq "") {
				$users = 20;
			}
			if ($public eq "") {
				$public = 1;
			}
			sendChatRoomChange($net, $title, $users, $public, $password);
		}

	} elsif ($arg1 eq "kick") {
		my ($arg2) = $args =~ /^\w+ (\d+)/;

		if ($currentChatRoom eq "") {
			error T("Error in function 'chat kick' (Kick from Chat)\n" .
				"You are not in a Chat Room.\n");
		} elsif ($arg2 eq "") {
			error T("Syntax Error in function 'chat kick' (Kick from Chat)\n" .
				"Usage: chat kick <user #>\n");
		} elsif ($currentChatRoomUsers[$arg2] eq "") {
			error TF("Error in function 'chat kick' (Kick from Chat)\n" .
				"Chat Room User %s doesn't exist\n", $arg2);
		} else {
			sendChatRoomKick($net, $currentChatRoomUsers[$arg2]);
		}

	} elsif ($arg1 eq "join") {
		my ($arg2) = $args =~ /^\w+ (\d+)/;
		my ($arg3) = $args =~ /^\w+ \d+ (\d+)/;

		if ($arg2 eq "") {
			error T("Syntax Error in function 'chat join' (Join Chat Room)\n" .
				"Usage: chat join <chat room #> [<password>]\n");
		} elsif ($currentChatRoom ne "") {
			error T("Error in function 'chat join' (Join Chat Room)\n" .
				"You are already in a chat room.\n");
		} elsif ($chatRoomsID[$arg2] eq "") {
			error TF("Error in function 'chat join' (Join Chat Room)\n" .
				"Chat Room %s does not exist.\n", $arg2);
		} else {
			sendChatRoomJoin($net, $chatRoomsID[$arg2], $arg3);
		}

	} elsif ($arg1 eq "leave") {
		if ($currentChatRoom eq "") {
			error T("Error in function 'chat leave' (Leave Chat Room)\n" .
				"You are not in a Chat Room.\n");
		} else {
			sendChatRoomLeave($net);
		}

	} elsif ($arg1 eq "create") {
		my ($title) = $args =~ /^\w+ \"([\s\S]*?)\"/;
		my ($users) = $args =~ /^\w+ \"[\s\S]*?\" (\d+)/;
		my ($public) = $args =~ /^\w+ \"[\s\S]*?\" \d+ (\d+)/;
		my ($password) = $args =~ /^\w+ \"[\s\S]*?\" \d+ \d+ ([\s\S]+)/;

		if ($title eq "") {
			error T("Syntax Error in function 'chat create' (Create Chat Room)\n" .
				"Usage: chat create \"<title>\" [<limit #> <public flag> <password>]\n");
		} elsif ($currentChatRoom ne "") {
			error T("Error in function 'chat create' (Create Chat Room)\n" .
				"You are already in a chat room.\n");
		} else {
			if ($users eq "") {
				$users = 20;
			}
			if ($public eq "") {
				$public = 1;
			}
			$title = ($config{chatTitleOversize}) ? $title : substr($title,0,36);
			sendChatRoomCreate($net, $title, $users, $public, $password);
			$createdChatRoom{'title'} = $title;
			$createdChatRoom{'ownerID'} = $accountID;
			$createdChatRoom{'limit'} = $users;
			$createdChatRoom{'public'} = $public;
			$createdChatRoom{'num_users'} = 1;
			$createdChatRoom{'users'}{$char->{name}} = 2;
		}

	} elsif ($arg1 eq "list") {
		message T("------------------------------- Chat Room List --------------------------------\n" .
			"#   Title                                  Owner                Users   Type\n"), "list";
		for (my $i = 0; $i < @chatRoomsID; $i++) {
			next if ($chatRoomsID[$i] eq "");
			my $owner_string = Actor::get($chatRooms{$chatRoomsID[$i]}{'ownerID'})->name;
			my $public_string = ($chatRooms{$chatRoomsID[$i]}{'public'}) ? "Public" : "Private";
			my $limit_string = $chatRooms{$chatRoomsID[$i]}{'num_users'}."/".$chatRooms{$chatRoomsID[$i]}{'limit'};
			message(swrite(
				"@<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<< @<<<<<< @<<<<<<",
				[$i, $chatRooms{$chatRoomsID[$i]}{'title'}, $owner_string, $limit_string, $public_string]),
				"list");
		}
		message("-------------------------------------------------------------------------------\n", "list");

	} elsif ($arg1 eq "info") {
		if ($currentChatRoom eq "") {
			error T("There is no chat room info - you are not in a chat room\n");
		} else {
			message T("-----------Chat Room Info-----------\n" .
				"Title                     Users   Public/Private\n"), "list";
			my $public_string = ($chatRooms{$currentChatRoom}{'public'}) ? "Public" : "Private";
			my $limit_string = $chatRooms{$currentChatRoom}{'num_users'}."/".$chatRooms{$currentChatRoom}{'limit'};

			message(swrite(
				"@<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<< @<<<<<<<<<",
				[$chatRooms{$currentChatRoom}{'title'}, $limit_string, $public_string]),
				"list");

			# Translation Comment: Users in chat room
			message T("-- Users --\n"), "list";
			for (my $i = 0; $i < @currentChatRoomUsers; $i++) {
				next if ($currentChatRoomUsers[$i] eq "");
				my $user_string = $currentChatRoomUsers[$i];
				my $admin_string = ($chatRooms{$currentChatRoom}{'users'}{$currentChatRoomUsers[$i]} > 1) ? "(Admin)" : "";
				message(swrite(
					"@<< @<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<",
					[$i, $user_string, $admin_string]),
					"list");
			}
			message("------------------------------------\n", "list");
		}
	} else {
		error T("Syntax Error in function 'chat' (Chat room management)\n" .
			"Usage: chat <create|modify|join|kick|leave|info|list|bestow>\n");
	}

}

sub cmdChist {
	# Display chat history
	my (undef, $args) = @_;
	$args = 5 if ($args eq "");

	if (!($args =~ /^\d+$/)) {
		error T("Syntax Error in function 'chist' (Show Chat History)\n" .
			"Usage: chist [<number of entries #>]\n");

	} elsif (open(CHAT, "<:utf8", $Settings::chat_file)) {
		my @chat = <CHAT>;
		close(CHAT);
		message T("------ Chat History --------------------\n"), "list";
		my $i = @chat - $args;
		$i = 0 if ($i < 0);
		for (; $i < @chat; $i++) {
			message($chat[$i], "list");
		}
		message "----------------------------------------\n", "list";

	} else {
		error TF("Unable to open %s\n", $Settings::chat_file);
	}
}

sub cmdCloseShop {
	main::closeShop();
}

sub cmdConf {
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^(\w+)/;
	my ($arg2) = $args =~ /^\w+\s+([\s\S]+)\s*$/;

	if ($arg1 eq "") {
		error T("Syntax Error in function 'conf' (Change a Configuration Key)\n" .
			"Usage: conf <variable> [<value>|none]\n");

	} elsif (!exists $config{$arg1}) {
		error TF("Config variable %s doesn't exist\n", $arg1);

	} elsif ($arg2 eq "") {
		my $value = $config{$arg1};
		if ($arg1 =~ /password/i) {
			message TF("Config '%s' is not displayed\n", $arg1), "info";
		} else {
			message TF("Config '%s' is %s\n", $arg1, $value), "info";
		}

	} else {
		undef $arg2 if ($arg2 eq "none");
		Plugins::callHook('Commands::cmdConf', {
			key => $arg1,
			val => \$arg2
		});
		configModify($arg1, $arg2);
		Log::initLogFiles();
	}
}

sub cmdDamage {
	my (undef, $args) = @_;
	
	if ($args eq "") {
		my $total = 0;
		message T("Damage Taken Report:\n"), "list";
		message(sprintf("%-40s %-20s %-10s\n", 'Name', 'Skill', 'Damage'), "list");
		for my $monsterName (sort keys %damageTaken) {
			my $monsterHref = $damageTaken{$monsterName};
			for my $skillName (sort keys %{$monsterHref}) {
				message sprintf("%-40s %-20s %10d\n", $monsterName, $skillName, $monsterHref->{$skillName}), "list";
				$total += $monsterHref->{$skillName};
			}
		}
		message TF("Total Damage Taken: %s\n", $total), "list";
		message T("End of report.\n"), "list";

	} elsif ($args eq "reset") {
		undef %damageTaken;
		message T("Damage Taken Report reset.\n"), "success";
	} else {
		error T("Syntax error in function 'damage' (Damage Report)\n" .
			"Usage: damage [reset]\n");
	}
}

sub cmdDeal {
	my (undef, $args) = @_;
	my @arg = split / /, $args;

	if (%currentDeal && $arg[0] =~ /\d+/) {
		error T("Error in function 'deal' (Deal a Player)\n" .
			"You are already in a deal\n");
	} elsif (%incomingDeal && $arg[0] =~ /\d+/) {
		error T("Error in function 'deal' (Deal a Player)\n" .
			"You must first cancel the incoming deal\n");
	} elsif ($arg[0] =~ /\d+/ && !$playersID[$arg[0]]) {
		error TF("Error in function 'deal' (Deal a Player)\n" .
			"Player %s does not exist\n", $arg[0]);
	} elsif ($arg[0] =~ /\d+/) {
		my $ID = $playersID[$arg[0]];
		my $player = Actor::get($ID);
		message TF("Attempting to deal %s\n", $player);
		deal($player);

	} elsif ($arg[0] eq "no" && !%incomingDeal && !%outgoingDeal && !%currentDeal) {
		error T("Error in function 'deal' (Deal a Player)\n" .
			"There is no incoming/current deal to cancel\n");
	} elsif ($arg[0] eq "no" && (%incomingDeal || %outgoingDeal)) {
		sendDealCancel();
	} elsif ($arg[0] eq "no" && %currentDeal) {
		sendCurrentDealCancel();

	} elsif ($arg[0] eq "" && !%incomingDeal && !%currentDeal) {
		error T("Error in function 'deal' (Deal a Player)\n" .
			"There is no deal to accept\n");
	} elsif ($arg[0] eq "" && $currentDeal{'you_finalize'} && !$currentDeal{'other_finalize'}) {
		error TF("Error in function 'deal' (Deal a Player)\n" .
			"Cannot make the trade - %s has not finalized\n", $currentDeal{'name'});
	} elsif ($arg[0] eq "" && $currentDeal{'final'}) {
		error T("Error in function 'deal' (Deal a Player)\n" .
			"You already accepted the final deal\n");
	} elsif ($arg[0] eq "" && %incomingDeal) {
		sendDealAccept();
	} elsif ($arg[0] eq "" && $currentDeal{'you_finalize'} && $currentDeal{'other_finalize'}) {
		sendDealTrade();
		$currentDeal{'final'} = 1;
		message T("You accepted the final Deal\n"), "deal";
	} elsif ($arg[0] eq "" && %currentDeal) {
		sendDealAddItem(0, $currentDeal{'you_zenny'});
		sendDealFinalize();

	} elsif ($arg[0] eq "add" && !%currentDeal) {
		error T("Error in function 'deal_add' (Add Item to Deal)\n" .
			"No deal in progress\n");
	} elsif ($arg[0] eq "add" && $currentDeal{'you_finalize'}) {
		error T("Error in function 'deal_add' (Add Item to Deal)\n" .
			"Can't add any Items - You already finalized the deal\n");
	} elsif ($arg[0] eq "add" && $arg[1] =~ /\d+/ && ( !$char->{'inventory'}[$arg[1]] || !%{$char->{'inventory'}[$arg[1]]} )) {
		error TF("Error in function 'deal_add' (Add Item to Deal)\n" .
			"Inventory Item %s does not exist.\n", $arg[1]);
	} elsif ($arg[0] eq "add" && $arg[2] && $arg[2] !~ /\d+/) {
		error T("Error in function 'deal_add' (Add Item to Deal)\n" .
			"Amount must either be a number, or not specified.\n");
	} elsif ($arg[0] eq "add" && $arg[1] =~ /\d+/) {
		if ($currentDeal{you_items} < 10) {
			if (!$arg[2] || $arg[2] > $char->{'inventory'}[$arg[1]]{'amount'}) {
				$arg[2] = $char->{'inventory'}[$arg[1]]{'amount'};
			}
			dealAddItem($char->{inventory}[$arg[1]], $arg[2]);
		} else {
			error T("You can't add any more items to the deal\n"), "deal";
		}
	} elsif ($arg[0] eq "add" && $arg[1] eq "z") {
		if (!$arg[2] || $arg[2] > $char->{'zenny'}) {
			$arg[2] = $char->{'zenny'};
		}
		$currentDeal{'you_zenny'} = $arg[2];
		message TF("You put forward %sz to Deal\n", formatNumber($arg[2])), "deal";

	} else {
		error T("Syntax Error in function 'deal' (Deal a player)\n" .
			"Usage: deal [<Player # | no | add>] [<item #>] [<amount>]\n");
	}
}

sub cmdDealList {
	if (!%currentDeal) {
		error T("There is no deal list - You are not in a deal\n");

	} else {
		message T("-----------Current Deal-----------\n"), "list";
		my $other_string = $currentDeal{'name'};
		my $you_string = "You";
		if ($currentDeal{'other_finalize'}) {
			$other_string .= " - Finalized";
		}
		if ($currentDeal{'you_finalize'}) {
			$you_string .= " - Finalized";
		}

		message(swrite(
			"@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<   @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<",
			[$you_string, $other_string]),
			"list");

		my @currentDealYou;
		my @currentDealOther;
		foreach (keys %{$currentDeal{'you'}}) {
			push @currentDealYou, $_;
		}
		foreach (keys %{$currentDeal{'other'}}) {
			push @currentDealOther, $_;
		}

		my ($lastindex, $display, $display2);
		$lastindex = @currentDealOther;
		$lastindex = @currentDealYou if (@currentDealYou > $lastindex);
		for (my $i = 0; $i < $lastindex; $i++) {
			if ($i < @currentDealYou) {
				$display = ($items_lut{$currentDealYou[$i]} ne "")
					? $items_lut{$currentDealYou[$i]}
					: "Unknown ".$currentDealYou[$i];
				$display .= " x $currentDeal{'you'}{$currentDealYou[$i]}{'amount'}";
			} else {
				$display = "";
			}
			if ($i < @currentDealOther) {
				$display2 = ($items_lut{$currentDealOther[$i]} ne "")
					? $items_lut{$currentDealOther[$i]}
					: "Unknown ".$currentDealOther[$i];
				$display2 .= " x $currentDeal{'other'}{$currentDealOther[$i]}{'amount'}";
			} else {
				$display2 = "";
			}

			message(swrite(
				"@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<   @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<",
				[$display, $display2]),
				"list");
		}
		$you_string = ($currentDeal{'you_zenny'} ne "") ? $currentDeal{'you_zenny'} : 0;
		$other_string = ($currentDeal{'other_zenny'} ne "") ? $currentDeal{'other_zenny'} : 0;

		message TF("Zenny: %-25s Zenny: %-14s", 
			formatNumber($you_string), formatNumber($other_string)), "list";
		message("----------------------------------\n", "list");
	}
}

sub cmdDebug {
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^([\w\d]+)/;

	if ($arg1 eq "0") {
		configModify("debug", 0);
	} elsif ($arg1 eq "1") {
		configModify("debug", 1);
	} elsif ($arg1 eq "2") {
		configModify("debug", 2);

	} elsif ($arg1 eq "info") {
		my $connected = "server=".($net->serverAlive ? "yes" : "no").
			",client=".($net->clientAlive ? "yes" : "no");
		my $time = sprintf("%.2f", time - $lastPacketTime);
		my $ai_timeout = sprintf("%.2f", time - $timeout{'ai'}{'time'});
		my $ai_time = sprintf("%.4f", time - $ai_v{'AI_last_finished'});

		message TF("------------ Debug information ------------\n" .
			"ConState: %s             Connected: %s\n" .
			"AI enabled: %s            AI_forcedOff: %s\n" .
			"\@ai_seq = %s\n" .
			"Last packet: %.2f secs ago\n" .
			"\$timeout{ai}: %.2f secs ago  (value should be >%s)\n" .
			"Last AI() call: %.2f secs ago\n" .
			"-------------------------------------------\n",
		$conState, $connected, $AI, $AI_forcedOff, @ai_seq, $time, $ai_timeout, 
		$timeout{'ai'}{'timeout'}, $ai_time), "list";
	}
}

sub cmdDoriDori {
	my $headdir;
	if ($char->{look}{head} == 2) {
		$headdir = 1;
	} else {
		$headdir = 2;
	}
	sendLook($net, $char->{look}{body}, $headdir);
}

sub cmdDrop {
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^([\d,-]+)/;
	my ($arg2) = $args =~ /^[\d,-]+ (\d+)$/;
	if ($arg1 eq "") {
		error T("Syntax Error in function 'drop' (Drop Inventory Item)\n" .	
			"Usage: drop <item #> [<amount>]\n");
	} else {
		my @temp = split(/,/, $arg1);
		@temp = grep(!/^$/, @temp); # Remove empty entries

		my @items = ();
		foreach (@temp) {
			if (/(\d+)-(\d+)/) {
				for ($1..$2) {
					push(@items, $_) if ($char->{inventory}[$_] && %{$char->{inventory}[$_]});
				}
			} else {
				push @items, $_ if ($char->{inventory}[$_] && %{$char->{inventory}[$_]});
			}
		}
		if (@items > 0) {
			main::ai_drop(\@items, $arg2);
		} else {
			error T("No items were dropped.\n");
		}
	}
}

sub cmdDump {
	dumpData($msg);
	quit();
}

sub cmdDumpNow {
	dumpData($msg);
}

sub cmdEmotion {
	# Show emotion
	my (undef, $args) = @_;

	my $num = getEmotionByCommand($args);

	if (!defined $num) {
		error T("Syntax Error in function 'e' (Emotion)\n" .
			"Usage: e <command>\n");
	} else {
		sendEmotion($net, $num);
	}
}

sub cmdEquip {
	# Equip an item
	my (undef, $args) = @_;
	my ($arg1,$arg2) = $args =~ /^(\S+)\s*(.*)/;
	my $slot;
	my $item;

	if ($arg1 eq "") {
		cmdEquip_list();
		return;
	}

	if ($arg1 eq "slots") {
		# Translation Comment: List of equiped items on each slot
		message T("Slots:\n") . join("\n", @Actor::Item::slots). "\n", "list";
		return;
	}

	if ($equipSlot_rlut{$arg1}) {
		$slot = $arg1;
	} else {
		$arg1 .= " $arg2" if $arg2;
	}

	$item = Actor::Item::get(defined $slot ? $arg2 : $arg1, undef, 1);

	if (!$item) {
		error TF("You don't have %s.\n", $arg1);
		return;
	}

	if (!$item->{type_equip} && $item->{type} != 10) {
		error TF("Inventory Item %s (%s) can't be equipped.\n", 
			$item->{name}, $item->{invIndex});
		return;
	}
	if ($slot) {
		$item->equipInSlot($slot);
	}
	else {
		$item->equip();
	}
}

sub cmdEquip_list {
	for my $slot (@Actor::Item::slots) {
		my $item = $char->{equipment}{$slot};
		my $name = $item ? $item->nameString : '-';
		message sprintf("%-15s: %s\n", $slot, $name), "list";
	}
}

sub cmdEval {
	if ($_[1] eq "") {
		error T("Syntax Error in function 'eval' (Evaluate a Perl expression)\n" .
			"Usage: eval <expression>\n");
	} else {
		package main;
		no strict;
		undef $@;
		eval $_[1];
		Log::error("$@") if ($@);
	}
}

sub cmdExp {
	my (undef, $args) = @_;
	my $knownArg;
	
	# exp report
	my ($arg1) = $args =~ /^(\w+)/;
	
	if (($arg1 eq "") || ($arg1 eq "report")) {
		$knownArg = 1;
		my ($endTime_EXP, $w_sec, $bExpPerHour, $jExpPerHour, $EstB_sec, $percentB, $percentJ, $zennyMade, $zennyPerHour, $EstJ_sec, $percentJhr, $percentBhr);
		$endTime_EXP = time;
		$w_sec = int($endTime_EXP - $startTime_EXP);
		if ($w_sec > 0) {
			$zennyMade = $char->{zenny} - $startingZenny;
			$bExpPerHour = int($totalBaseExp / $w_sec * 3600);
			$jExpPerHour = int($totalJobExp / $w_sec * 3600);
			$zennyPerHour = int($zennyMade / $w_sec * 3600);
			if ($char->{exp_max} && $bExpPerHour){
				$percentB = "(".sprintf("%.2f",$totalBaseExp * 100 / $char->{exp_max})."%)";
				$percentBhr = "(".sprintf("%.2f",$bExpPerHour * 100 / $char->{exp_max})."%)";
				$EstB_sec = int(($char->{exp_max} - $char->{exp})/($bExpPerHour/3600));
			}
			if ($char->{exp_job_max} && $jExpPerHour){
				$percentJ = "(".sprintf("%.2f",$totalJobExp * 100 / $char->{exp_job_max})."%)";
				$percentJhr = "(".sprintf("%.2f",$jExpPerHour * 100 / $char->{exp_job_max})."%)";
				$EstJ_sec = int(($char->{'exp_job_max'} - $char->{exp_job})/($jExpPerHour/3600));
			}
		}
		$char->{deathCount} = 0 if (!defined $char->{deathCount});
		message TF( "------------Exp Report------------\n" .
					"Botting time : %s\n" .
					"BaseExp      : %s %s\n" .
					"JobExp       : %s %s\n" .
					"BaseExp/Hour : %s %s\n" .
					"JobExp/Hour  : %s %s\n" .
					"Zenny        : %s\n" .
					"Zenny/Hour   : %s\n" .
					"Base Levelup Time Estimation : %s\n" .
					"Job Levelup Time Estimation  : %s\n" .
					"Died : %s\n" .
					"Bytes Sent   : %s\n" .
					"Bytes Rcvd   : %s\n",
			timeConvert($w_sec), formatNumber($totalBaseExp), $percentB, formatNumber($totalJobExp), $percentJ,
			formatNumber($bExpPerHour), $percentBhr, formatNumber($jExpPerHour), $percentJhr,
			formatNumber($zennyMade), formatNumber($zennyPerHour), timeConvert($EstB_sec), timeConvert($EstJ_sec), 
			$char->{'deathCount'}, formatNumber($bytesSent), formatNumber($bytesReceived)), "info";
			
		if ($arg1 eq "") {
			message("---------------------------------\n", "list");
		}
	}
	
	if (($arg1 eq "monster") || ($arg1 eq "report")) {
		my $total;
 
		$knownArg = 1;

		message T("-[Monster Killed Count]-----------------------\n" .
			"#   ID     Name                      Count\n"), "list";
		for (my $i = 0; $i < @monsters_Killed; $i++) {
			next if ($monsters_Killed[$i] eq "");
			message(swrite(
				"@<< @<<<<< @<<<<<<<<<<<<<<<<<<<<<<<< @<<< ",
				[$i, $monsters_Killed[$i]{nameID}, $monsters_Killed[$i]{name}, $monsters_Killed[$i]{count}]),
				"list");
			$total += $monsters_Killed[$i]{count};
		}
		message("----------------------------------------------\n" .
			TF("Total number of killed monsters: %s\n", $total) .
			"----------------------------------------------\n",
			"list");
	}

	if (($arg1 eq "item") || ($arg1 eq "report")) {
		$knownArg = 1;

		message T("-[Item Change Count]--------------------------\n" .
			"Name                                    Count\n"), "list";
		for my $item (sort keys %itemChange) {
			next unless $itemChange{$item};
			message(sprintf("%-40s %5d\n", $item, $itemChange{$item}), "list");
		}
		message("----------------------------------------------\n", "list");

	}
	
	if ($arg1 eq "reset") {
		$knownArg = 1;
		($bExpSwitch,$jExpSwitch,$totalBaseExp,$totalJobExp) = (2,2,0,0);
		$startTime_EXP = time;
		$startingZenny = $char->{zenny};
		undef @monsters_Killed;
		$dmgpsec = 0;
		$totaldmg = 0;
		$elasped = 0;
		$totalelasped = 0;
		undef %itemChange;
		$bytesSent = 0;
		$bytesReceived = 0;
		message T("Exp counter reset.\n"), "success";
	}
	
	if (!$knownArg) {
		error T("Syntax error in function 'exp' (Exp Report)\n" .
			"Usage: exp [<report | monster | item | reset>]\n");
	}
}

sub cmdFalcon {
	my (undef, $arg1) = @_;

	if ($arg1 eq "") {
		if (hasFalcon()) {
			message T("Your falcon is active\n");
		} else {
			message T("Your falcon is inactive\n");
		}
	} elsif ($arg1 eq "release") {
		if (!hasFalcon()) {
		error T("Error in function 'falcon release' (Remove Falcon Status)\n" .
			"You don't possess a falcon.\n");
		} else {
			sendCompanionRelease();
		}
	}
}

sub cmdFollow {
	my (undef, $arg1) = @_;
	if ($arg1 eq "") {
		error T("Syntax Error in function 'follow' (Follow Player)\n" .
			"Usage: follow <player #>\n");
	} elsif ($arg1 eq "stop") {
		AI::clear("follow");
		configModify("follow", 0);
	} elsif ($arg1 =~ /^\d+$/) {
		if (!$playersID[$arg1]) {
			error TF("Error in function 'follow' (Follow Player)\n" .
				"Player %s either not visible or not online in party.\n", $arg1);
		} else {
			AI::clear("follow");
			main::ai_follow($players{$playersID[$arg1]}->name);
			configModify("follow", 1);
			configModify("followTarget", $players{$playersID[$arg1]}{name});
		}

	} else {
		AI::clear("follow");
		main::ai_follow($arg1);
		configModify("follow", 1);
		configModify("followTarget", $arg1);
	}
}

sub cmdFriend {
	my (undef, $args) = @_;
	my ($arg1, $arg2) = split(' ', $args, 2);

	if ($arg1 eq "request") {
		my $player = Match::player($arg2);

		if (!$player) {
			error TF("Player %s does not exist\n", $arg2);
		} elsif (!defined $player->{name}) {
			error T("Player name has not been received, please try again\n");
		} else {
			my $alreadyFriend = 0;
			for (my $i = 0; $i < @friendsID; $i++) {
				if ($friends{$i}{'name'} eq $player->{name}) {
					$alreadyFriend = 1;
					last;
				}
			}
			if ($alreadyFriend) {
				error TF("%s is already your friend\n", $player->{name});
			} else {
				message TF("Requesting %s to be your friend\n", $player->{name});
				sendFriendRequest($net, $players{$playersID[$arg2]}{name});
			}
		}

	} elsif ($arg1 eq "remove") {
		if ($arg2 < 1 || $arg2 > @friendsID) {
			error TF("Friend #%s does not exist\n", $arg2);
		} else {
			$arg2--;
			message TF("Attempting to remove %s from your friend list\n", $friends{$arg2}{'name'});
			sendFriendRemove($net, $friends{$arg2}{'accountID'}, $friends{$arg2}{'charID'});
		}

	} elsif ($arg1 eq "accept") {
		if ($incomingFriend{'accountID'} eq "") {
			error T("Can't accept the friend request, no incoming request\n");
		} else {
			message TF("Accepting the friend request from %s\n", $incomingFriend{'name'});
			sendFriendAccept($net, $incomingFriend{'accountID'}, $incomingFriend{'charID'});
			undef %incomingFriend;
		}

	} elsif ($arg1 eq "reject") {
		if ($incomingFriend{'accountID'} eq "") {
			error T("Can't reject the friend request - no incoming request\n");
		} else {
			message TF("Rejecting the friend request from %s\n", $incomingFriend{'name'});
			sendFriendReject($net, $incomingFriend{'accountID'}, $incomingFriend{'charID'});
			undef %incomingFriend;
		}

	} elsif ($arg1 eq "pm") {
		if ($arg2 < 1 || $arg2 > @friendsID) {
			error TF("Friend #%s does not exist\n", $arg2);
		} else {
			$arg2--;
			if (binFind(\@privMsgUsers, $friends{$arg2}{'name'}) eq "") {
				message TF("Friend %s has been added to the PM list as %s\n", $friends{$arg2}{'name'}, @privMsgUsers);
				$privMsgUsers[@privMsgUsers] = $friends{$arg2}{'name'};
			} else {
				message TF("Friend %s is already in the PM list\n", $friends{$arg2}{'name'});
			}
		}

	} elsif ($arg1 ne "") {
		error T("Syntax Error in function 'friend' (Manage Friends List)\n" .
			"Usage: friend [request|remove|accept|reject|pm]\n");

	} else {
		message T("------------- Friends --------------\n" .
			"#   Name                      Online\n"), "list";
		for (my $i = 0; $i < @friendsID; $i++) {
			message(swrite(
				"@<  @<<<<<<<<<<<<<<<<<<<<<<<  @",
				[$i + 1, $friends{$i}{'name'}, $friends{$i}{'online'}? 'X':'']),
				"list");
		}
		message("----------------------------------\n", "list");
	}

}

sub cmdHomunculus {
 	my (undef, $subcmd) = @_;
	my @args = parseArgs($subcmd);

	if (!$char->{homunculus} || !$char->{homunculus}{appear_time} || ($char->{homunculus}{state} > 1)) {
		error T("Error: No Homunculus detected.\n");

	} elsif ($subcmd eq "s" || $subcmd eq "status") {
		my $hp_string = $char->{'homunculus'}{'hp'}. '/' .$char->{'homunculus'}{'hp_max'} . ' (' . sprintf("%.2f",$char->{'homunculus'}{'hpPercent'}) . '%)';
		my $sp_string = $char->{'homunculus'}{'sp'}."/".$char->{'homunculus'}{'sp_max'}." (".sprintf("%.2f",$char->{'homunculus'}{'spPercent'})."%)";
		my $exp_string = formatNumber($char->{'homunculus'}{'exp'})."/".formatNumber($char->{'homunculus'}{'exp_max'})." (".sprintf("%.2f",$char->{'homunculus'}{'expPercent'})."%)";
		
		my $msg = swrite(
		T("----------------- Homunculus Status --------------------\n" .
		"Name: \@<<<<<<<<<<<<<<<<<<<<<<<<< HP: \@>>>>>>>>>>>>>>>>>>\n" .
		"                                 SP: \@>>>>>>>>>>>>>>>>>>\n" .
		"Level: \@<<   \@>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\n" .
		"--------------------------------------------------------\n" .
		"Atk: \@>>>    Matk:     \@>>>    Hunger:    \@>>>\n" .
		"Hit: \@>>>    Critical: \@>>>    Intimacy:  \@>>>\n" .
		"Def: \@>>>    Mdef:     \@>>>    Accessory: \@>>>\n" .
		"Flee:\@>>>    Aspd:     \@>>>\n" .
		"--------------------------------------------------------"),
		[$char->{'homunculus'}{'name'}, $hp_string, $sp_string,
		$char->{'homunculus'}{'level'}, $exp_string, $char->{'homunculus'}{'atk'}, $char->{'homunculus'}{'matk'}, $char->{'homunculus'}{'hunger'},
		$char->{'homunculus'}{'hit'}, $char->{'homunculus'}{'critical'}, $char->{'homunculus'}{'intimacy'},
		$char->{'homunculus'}{'def'}, $char->{'homunculus'}{'mdef'}, $char->{'homunculus'}{'accessory'},
		$char->{'homunculus'}{'flee'}, $char->{'homunculus'}{'aspdDisp'}]);
			
		message($msg, "info");

	} elsif ($subcmd eq "feed") {
		if ($char->{homunculus}{hunger} >= 76) {
			message T("Your homunculus is not yet hungry. Feeding it now will lower intimacy.\n"), "homunculus";
		} else {
			$net->sendHomunculusFeed();
			message T("Feeding your homunculus.\n"), "homunculus";
		}

	} elsif ($args[0] eq "move") {
		if (!($args[1] =~ /^\d+$/) || !($args[2] =~ /^\d+$/)) {
			error TF("Error in function 'homun move' (Homunculus Move)\n" .
				"Invalid coordinates (%s, %s) specified.\n", $args[1], $args[2]);
			return;
		} else {
			# max distance that homunculus can follow: 17
			$net->sendHomunculusMove($char->{homunculus}{ID}, $args[1], $args[2]);
		}

	} elsif ($subcmd eq "standby") {
		$net->sendHomunculusStandBy($char->{homunculus}{ID});

	} elsif ($args[0] eq 'ai') {
		if ($args[1] eq 'clear') {
			AI::Homunculus::clear();
			message T("Homunculus AI sequences cleared\n"), "success";

		} elsif ($args[1] eq 'print') {
			# Display detailed info about current AI sequence
			message T("------ Homunculus AI Sequence ----------\n"), "list";
			my $index = 0;
			foreach (@AI::Homunculus::homun_ai_seq) {
				message("$index: $_ " . dumpHash(\%{$ai_seq_args[$index]}) . "\n\n", "list");
				$index++;
			}

			message T("------ Homunculus AI Sequence ----------\n"), "list";

		} elsif ($args[1] eq 'on' || $args[1] eq 'auto') {
			# Set AI to auto mode
			if ($AI::Homunculus::homun_AI == 2) {
				message T("Homunculus AI is already set to auto mode\n"), "success";
			} else {
				$AI::Homunculus::homun_AI = 2;
				undef $AI::Homunculus::homun_AI_forcedOff;
				message T("Homunculus AI set to auto mode\n"), "success";
			}
		} elsif ($args[1] eq 'manual') {
			# Set AI to manual mode
			if ($AI::Homunculus::homun_AI == 1) {
				message T("Homunculus AI is already set to manual mode\n"), "success";
			} else {
				$AI::Homunculus::homun_AI = 1;
				$AI::Homunculus::homun_AI_forcedOff = 1;
				message T("Homunculus AI set to manual mode\n"), "success";
			}
		} elsif ($args[1] eq 'off') {
			# Turn AI off
			if ($AI::Homunculus::homun_AI) {
				undef $AI::Homunculus::homun_AI;
				$AI::Homunculus::homun_AI_forcedOff = 1;
				message T("Homunculus AI turned off\n"), "success";
			} else {
				message T("Homunculus AI is already off\n"), "success";
			}

		} elsif ($args[1] eq '') {
			# Toggle AI
			if ($AI::Homunculus::homun_AI == 2) {
				undef $AI::Homunculus::homun_AI;
				$AI::Homunculus::homun_AI_forcedOff = 1;
				message T("Homunculus AI turned off\n"), "success";
			} elsif (!$AI::Homunculus::homun_AI) {
				$AI::Homunculus::homun_AI = 1;
				$AI::Homunculus::homun_AI_forcedOff = 1;
				message T("Homunculus AI set to manual mode\n"), "success";
			} elsif ($AI::Homunculus::homun_AI == 1) {
				$AI::Homunculus::homun_AI = 2;
				undef $AI::Homunculus::homun_AI_forcedOff;
				message T("Homunculus AI set to auto mode\n"), "success";
			}

		} else {
			error T("Syntax Error in function 'homun ai' (Homunculus AI Commands)\n" .
				"Usage: homun ai [ clear | print | auto | manual | off ]\n");
		}

	} elsif ($subcmd eq "aiv") {
		if (!$AI::Homunculus::homun_AI) {
			message TF("ai_seq (off) = %s\n", "@AI::Homunculus::homun_ai_seq"), "list";
		} elsif ($AI::Homunculus::homun_AI == 1) {
			message TF("ai_seq (manual) = %s\n", "@AI::Homunculus::homun_ai_seq"), "list";
		} elsif ($AI::Homunculus::homun_AI == 2) {
			message TF("ai_seq (auto) = %s\n", "@AI::Homunculus::homun_ai_seq"), "list";
		}
		message T("solution\n"), "list" if (AI::Homunculus::args()->{'solution'});

	} elsif ($args[0] eq "skills") {
		if ($args[1] eq '') {
			my $msg = T("-----Homunculus Skill List-----\n" .
				"   # Skill Name                     Lv      SP\n");
			for my $handle (@AI::Homunculus::homun_skillsID) {
				my $skill = Skills->new(handle => $handle);
				my $sp = $char->{skills}{$handle}{sp} || '';
				$msg .= swrite(
					"@>>> @<<<<<<<<<<<<<<<<<<<<<<<<<<<< @>>    @>>>",
					[$skill->id, $skill->name, $char->{skills}{$handle}{lv}, $sp]);
			}
			$msg .= TF("\nSkill Points: %d\n", $char->{homunculus}{points_skill});
			$msg .= "-------------------------------\n";
			message($msg, "list");

		} elsif ($args[1] eq "add" && $args[2] =~ /\d+/) {
			my $skill = Skills->new(id => $args[2]);
			if (!$skill->id || !$char->{skills}{$skill->handle}) {
				error TF("Error in function 'homun skills add' (Add Skill Point)\n" .
					"Skill %s does not exist.\n", $args[2]);
			} elsif ($char->{homunculus}{points_skill} < 1) {
				error TF("Error in function 'homun skills add' (Add Skill Point)\n" .
					"Not enough skill points to increase %s\n", $skill->name);
			} else {
				$net->sendAddSkillPoint($skill->id);
			}

		} elsif ($args[1] eq "desc" && $args[2] =~ /\d+/) {
			my $skill = Skills->new(id => $args[2]);
			if (!$skill->id) {
				error TF("Error in function 'homun skills desc' (Skill Description)\n" .
					"Skill %s does not exist.\n", $args[2]);
			} else {
				my $description = $skillsDesc_lut{$skill->handle} || T("Error: No description available.\n");
				message TF("===============Skill Description===============\n" .
					"Skill: %s\n\n", $skill->name), "info";
				message $description, "info";
				message "==============================================\n", "info";
			}

		} else {
			error T("Syntax Error in function 'homun skills' (Homunculus Skills Functions)\n" .
				"Usage: homun skills [(<add | desc>) [<skill #>]]\n");
		}

 	} else {
		error T("Usage: homun < feed | s | status | move | standby | ai | aiv | skills>\n");
	}
}

sub cmdGetPlayerInfo {
	my (undef, $args) = @_;
	sendGetPlayerInfo($net, pack("V", $args));
}

sub cmdGuild {
	my (undef, $args) = @_;
	my ($arg1, $arg2) = split(' ', $args, 2);

	if ($arg1 eq "join") {
		if ($arg2 ne "1" && $arg2 ne "0") {
			error T("Syntax Error in function 'guild join' (Accept/Deny Guild Join Request)\n" .
				"Usage: guild join <flag>\n");
			return;
		} elsif ($incomingGuild{'ID'} eq "") {
			error T("Error in function 'guild join' (Join/Request to Join Guild)\n" .
				"Can't accept/deny guild request - no incoming request.\n");
			return;
		}

		sendGuildJoin($net, $incomingGuild{ID}, $arg2);
		undef %incomingGuild;
		if ($arg2) {
			message T("You accepted the guild join request.\n"), "success";
		} else {
			message T("You denied the guild join request.\n"), "info";
		}

	} elsif ($arg1 eq "create") {
		if (!$arg2) {
			error T("Syntax Error in function 'guild create' (Create Guild)\n" .
				"Usage: guild create <name>\n");
		} else {
			sendGuildCreate($arg2);
		}

	} elsif (!defined $char->{guild}) {
		error T("You are not in a guild.\n");

	} elsif ($arg1 eq "request") {
		my $player = Match::player($arg2);
		if (!$player) {
			error TF("Player %s does not exist.\n", $arg2);
		} else {
			sendGuildJoinRequest($player->{ID});
			message TF("Sent guild join request to %s\n", $player->{name});
		}

	} elsif ($arg1 eq "ally") {
		if (!$guild{master}) {
			error T("No guild information available. Type guild to refresh and then try again.\n");
			return;
		}
		my $player = Match::player($arg2);
		if (!$player) {
			error TF("Player %s does not exist.\n", $arg2);
		} elsif (!$char->{name} eq $guild{master}) {
			error T("You must be guildmaster to set an alliance\n");
			return;
		} else {
			sendGuildSetAlly($net,$player->{ID},$accountID,$charID);
			message TF("Sent guild alliance request to %s\n", $player->{name});
		}

	} elsif ($arg1 eq "leave") {
		sendGuildLeave($arg2);
		message TF("Sending guild leave: %s\n", $arg2);

	} elsif ($arg1 eq "break") {
		if (!$arg2) {
			error T("Syntax Error in function 'guild break' (Break Guild)\n" .
				"Usage: guild break <guild name>\n");
		} else {
			sendGuildBreak($arg2);
			message TF("Sending guild break: %s\n", $arg2);
		}

	} elsif ($arg1 eq "" || !%guild) {
		message	T("Requesting guild information...\n"), "info";
		sendGuildInfoRequest($net);

		# Replies 01B6 (Guild Info) and 014C (Guild Ally/Enemy List)
		sendGuildRequest($net, 0);

		# Replies 0166 (Guild Member Titles List) and 0154 (Guild Members List)
		sendGuildRequest($net, 1);

		if ($arg1 eq "") {
			message T("Enter command to view guild information: guild <info | member>\n"), "info";
		} else {
			message	TF("Type 'guild %s' again to view the information.\n", $args), "info";
		}

	} elsif ($arg1 eq "info") {
		message swrite(T("---------- Guild Information ----------\n" .
			"Name    : \@<<<<<<<<<<<<<<<<<<<<<<<<\n" .
			"Lv      : \@<<\n" .
			"Exp     : \@>>>>>>>>>/\@<<<<<<<<<<\n" .
			"Master  : \@<<<<<<<<<<<<<<<<<<<<<<<<\n" .
			"Connect : \@>>/\@<<"),
			[$guild{name}, $guild{lvl}, $guild{exp}, $guild{next_exp}, $guild{master}, 
			$guild{conMember}, $guild{maxMember}]),	"info";
		for my $ally (keys %{$guild{ally}}) {
			# Translation Comment: List of allies. Keep the same spaces of the - Guild Information - tag.
			message TF("Ally    : %s (%s)\n", $guild{ally}{$ally}, $ally), "info";
		}
		message("---------------------------------------\n", "info");

	} elsif ($arg1 eq "kick") {
		if (!$guild{member}) {
			error T("No guild member information available.\n");
			return;
		}
		my @params = split(' ', $arg2, 2);
		if ($params[0] =~ /^\d+$/) {
			if ($guild{'member'}[$params[0]]) {
				sendGuildMemberKick($char->{guildID},
					$guild{member}[$params[0]]{ID},
					$guild{member}[$params[0]]{charID},
					$params[1]);
			} else {
				error TF("Error in function 'guild kick' (Kick Guild Member)\n" .
					"Invalid guild member '%s' specified.\n", $params[0]);
			}
		} else {
			error T("Syntax Error in function 'guild kick' (Kick Guild Member)\n" .
				"Usage: guild kick <number> <reason>\n");
		}

	} elsif ($arg1 eq "member") {
		if (!$guild{member}) {
			error T("No guild member information available.\n");
			return;
		}

		my $msg = T("------------ Guild  Member ------------\n" .
			"#  Name                       Job        Lv  Title                    Online\n");

		my ($i, $name, $job, $lvl, $title, $online, $ID, $charID);
		my $count = @{$guild{member}};
		for ($i = 0; $i < $count; $i++) {
			$name  = $guild{member}[$i]{name};
			next if (!defined $name);

			$job   = $jobs_lut{$guild{member}[$i]{jobID}};
			$lvl   = $guild{member}[$i]{lvl};
			$title = $guild{member}[$i]{title};
 			# Translation Comment: Guild member online
			$online = $guild{member}[$i]{online} ? T("Yes") : T("No");
			$ID = unpack("V",$guild{member}[$i]{ID});
			$charID = unpack("V",$guild{member}[$i]{charID});

			$msg .= swrite("@< @<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<< @>  @<<<<<<<<<<<<<<<<<<<<<<< @<<",
					[$i, $name, $job, $lvl, $title, $online, $ID, $charID]);
		}
		$msg .= "---------------------------------------\n";
		message $msg, "list";

	}
}

sub cmdGuildChat {
	my (undef, $arg1) = @_;
	if ($arg1 eq "") {
		error T("Syntax Error in function 'g' (Guild Chat)\n" .
			"Usage: g <message>\n");
	} else {
		sendMessage($net, "g", $arg1);
	}
}

sub cmdHelp {
	# Display help message
	my (undef, $args) = @_;
	my @commands_req = split(/ +/, $args);
	my @unknown;
	my @found;

	my @commands = (@commands_req)? @commands_req : (sort keys %descriptions);

	my ($message,$cmd);

	$message .= T("--------------- Available commands ---------------\n") unless @commands_req;
	foreach my $switch (@commands) {
		if ($descriptions{$switch}) {
			if (ref($descriptions{$switch}) eq 'ARRAY') {
				if (@commands_req) {
					helpIndent($switch,$descriptions{$switch});
				} else {
					$message .= sprintf("%-11s  %s\n",$switch, $descriptions{$switch}->[0]);
				}
			}
			push @found, $switch;
		} else {
			push @unknown, $switch;
		}
	}

	@commands = (@commands_req)? @commands_req : (sort keys %customCommands);
	foreach my $switch (@commands) {
		if ($customCommands{$switch}) {
			if (ref($customCommands{$switch}{desc}) eq 'ARRAY') {
				if (@commands_req) {
					helpIndent($switch,$customCommands{$switch}{desc});
				} else {
					$message .= sprintf("%-11s  %s\n",$switch, $customCommands{$switch}{desc}->[0]);
				}
			}
			push @found, $switch;
		} else {
			push @unknown, $switch unless defined binFind(\@unknown,$switch);
		}
	}

	foreach (@found) {
		binRemoveAndShift(\@unknown,$_);
	}

	if (@unknown) {
		if (@unknown == 1) {
			error TF("The command \"%s\" doesn't exist.\n", $unknown[0]);
		} else {
			error TF("These commands don't exist: %s\n", join(', ', @unknown));
		}
		error T("Type 'help' to see a list of all available commands.\n");
	}
	$message .= "--------------------------------------------------\n"unless @commands_req;

	message $message, "list" unless @commands_req;
}

sub helpIndent {
	my $cmd = shift;
	my $desc = shift;
	my $message;
	my $messageTmp;
	my @words;
	my $length = 0;

	$message = TF("------------ Help for '%s' ------------\n", $cmd);
	$message .= shift(@{$desc}) . "\n";

	foreach (@{$desc}) {
		$length = length($_->[0]) if length($_->[0]) > $length;
	}
	my $pattern = "$cmd %-${length}s    %s\n";
	my $padsize = length($cmd) + $length + 5;
	my $pad = sprintf("%-${padsize}s", '');

	foreach (@{$desc}) {
		if ($padsize + length($_->[1]) > 79) {
			@words = split(/ /, $_->[1]);
			$message .= sprintf("$cmd %-${length}s    ", $_->[0]);
			$messageTmp = '';
			foreach my $word (@words) {
				if ($padsize + length($messageTmp) + length($word) + 1 > 79) {
					$message .= $messageTmp . "\n$pad";
					$messageTmp = '';
				} else {
					$messageTmp .= "$word ";
				}
			}
			$message .= $messageTmp."\n";
		}
		else {
			$message .= sprintf($pattern, $_->[0], $_->[1]);
		}
	}
	$message .= "--------------------------------------------------\n";
	message $message, "list";
}

sub cmdIdentify {
	my (undef, $arg1) = @_;
	if ($arg1 eq "") {
		message T("---------Identify List--------\n"), "list";
		for (my $i = 0; $i < @identifyID; $i++) {
			next if ($identifyID[$i] eq "");
			message(swrite(
				"@<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<",
				[$i, $char->{'inventory'}[$identifyID[$i]]{name}]),
				"list");
		}
		message("------------------------------\n", "list");

	} elsif ($arg1 =~ /^\d+$/) {
		if ($identifyID[$arg1] eq "") {
			error TF("Error in function 'identify' (Identify Item)\n" .
				"Identify Item %s does not exist\n", $arg1);
		} else {
			sendIdentify($net, $char->{'inventory'}[$identifyID[$arg1]]{'index'});
		}

	} else {
		error TF("Syntax Error in function 'identify' (Identify Item)\n" .
			"Usage: identify [<identify #>]\n");
	}
}

sub cmdIgnore {
	my (undef, $args) = @_;
	my ($arg1, $arg2) = $args =~ /^(\d+) ([\s\S]*)/;
	if ($arg1 eq "" || $arg2 eq "" || ($arg1 ne "0" && $arg1 ne "1")) {
		error T("Syntax Error in function 'ignore' (Ignore Player/Everyone)\n" .
			"Usage: ignore <flag> <name | all>\n");
	} else {
		if ($arg2 eq "all") {
			sendIgnoreAll($net, !$arg1);
		} else {
			sendIgnore($net, $arg2, !$arg1);
		}
	}
}

sub cmdIhist {
	# Display item history
	my (undef, $args) = @_;
	$args = 5 if ($args eq "");

	if (!($args =~ /^\d+$/)) {
		error T("Syntax Error in function 'ihist' (Show Item History)\n" .
			"Usage: ihist [<number of entries #>]\n");

	} elsif (open(ITEM, "<", $Settings::item_log_file)) {
		my @item = <ITEM>;
		close(ITEM);
		message T("------ Item History --------------------\n"), "list";
		my $i = @item - $args;
		$i = 0 if ($i < 0);
		for (; $i < @item; $i++) {
			message($item[$i], "list");
		}
		message("----------------------------------------\n", "list");

	} else {
		error TF("Unable to open %s\n", $Settings::item_log_file);
	}
}

sub cmdInventory {
	# Display inventory items
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^(\w+)/;
	my ($arg2) = $args =~ /^\w+ (.+)/;

	if (!$char->{'inventory'}) {
		error T("Inventory is empty\n");
		return;
	}

	if ($arg1 eq "" || $arg1 eq "eq" || $arg1 eq "neq" || $arg1 eq "u" || $arg1 eq "nu") {
		my @useable;
		my @equipment;
		my @uequipment;
		my @non_useable;
		my ($i, $display, $index, $sell);

		for ($i = 0; $i < @{$char->{inventory}}; $i++) {
			my $item = $char->{inventory}[$i];
			next unless $item && %{$item};

			if (($item->{type} == 3 ||
			     $item->{type} == 6 ||
				 $item->{type} == 10) && !$item->{equipped}) {
				push @non_useable, $i;
			} elsif ($item->{type} <= 2) {
				push @useable, $i;
			} else {
				my %eqp;
				$eqp{index} = $item->{index};
				$eqp{binID} = $i;
				$eqp{name} = $item->{name};
				$eqp{type} = $itemTypes_lut{$item->{type}};
				$eqp{equipped} = ($item->{type} == 10) ? $item->{amount} . " left" : $equipTypes_lut{$item->{equipped}};
				$eqp{equipped} .= " ($item->{equipped})";
				# Translation Comment: Mark to tell item not identified
				$eqp{identified} = " -- " . T("Not Identified") if !$item->{identified};
				if ($item->{equipped}) {
					push @equipment, \%eqp;
				} else {
					push @uequipment, \%eqp;
				}
			}
		}

		my $msg = T("-----------Inventory-----------\n");
		if ($arg1 eq "" || $arg1 eq "eq") {
			# Translation Comment: List of usable equipments
			$msg .= T("-- Equipment (Equipped) --\n");
			foreach my $item (@equipment) {
				$sell = defined(findIndex(\@sellList, "invIndex", $item->{binID})) ? T("Will be sold") : "";
				$display = sprintf("%-3d  %s -- %s", $item->{binID}, $item->{name}, $item->{equipped});
				$msg .= sprintf("%-57s %s\n", $display, $sell);
			}
		}
		if ($arg1 eq "" || $arg1 eq "neq") {
			# Translation Comment: List of equipments
			$msg .= T("-- Equipment (Not Equipped) --\n");
			foreach my $item (@uequipment) {
				$sell = defined(findIndex(\@sellList, "invIndex", $item->{binID})) ? T("Will be sold") : "";
				$display = sprintf("%-3d  %s (%s) %s", $item->{binID}, $item->{name}, $item->{type}, $item->{identified});
				$msg .= sprintf("%-57s %s\n", $display, $sell);
			}
		}
		if ($arg1 eq "" || $arg1 eq "nu") {
			# Translation Comment: List of non-usable items
			$msg .= T("-- Non-Usable --\n");
			for ($i = 0; $i < @non_useable; $i++) {
				$index = $non_useable[$i];
				$display = $char->{inventory}[$index]{name};
				$display .= " x $char->{inventory}[$index]{amount}";
				# Translation Comment: Tell if the item is marked to be sold 				
				$sell = defined(findIndex(\@sellList, "invIndex", $index)) ? T("Will be sold") : "";
				$msg .= swrite(
					"@<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<",
					[$index, $display, $sell]);
			}
		}
		if ($arg1 eq "" || $arg1 eq "u") {
			# Translation Comment: List of usable items
			$msg .= T("-- Usable --\n");
			for ($i = 0; $i < @useable; $i++) {
				$index = $useable[$i];
				$display = $char->{inventory}[$index]{name};
				$display .= " x $char->{inventory}[$index]{amount}";
				$sell = defined(findIndex(\@sellList, "invIndex", $index)) ? T("Will be sold") : "";
				$msg .= swrite(
					"@<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<",
					[$index, $display, $sell]);
			}
		}
		$msg .= "-------------------------------\n";
		message($msg, "list");

	} elsif ($arg1 eq "desc") {
		cmdInventory_desc($arg2);

	} else {
		error T("Syntax Error in function 'i' (Inventory List)\n" .
			"Usage: i [<u|eq|neq|nu|desc>] [<inventory item>]\n");
	}
}

sub cmdInventory_desc {
	my ($name) = @_;

	my $item = Match::inventoryItem($name);
	if (!$item) {
		error TF("Error in function 'i' (Inventory Item Description)\n" .
			"Inventory Item %s does not exist\n", $name);
		return;
	}

	printItemDesc($item->{nameID});
}

sub cmdItemList {
	message T("-----------Item List-----------\n" .
		"   # Name                           Coord\n"), "list";
	for (my $i = 0; $i < @itemsID; $i++) {
		next if ($itemsID[$i] eq "");
		my $item = $items{$itemsID[$i]};
		my $display = "$item->{name} x $item->{amount}";
		message(sprintf("%4d %-30s (%3d, %3d)\n",
			$i, $display, $item->{pos}{x}, $item->{pos}{y}),
			"list");
	}
	message("-------------------------------\n", "list");
}

sub cmdItemLogClear {
	itemLog_clear();
	message T("Item log cleared.\n"), "success";
}

#sub cmdJudge {
#	my (undef, $args) = @_;
#	my ($arg1) = $args =~ /^(\d+)/;
#	my ($arg2) = $args =~ /^\d+ (\d+)/;
#	if ($arg1 eq "" || $arg2 eq "") {
#		error	"Syntax Error in function 'judge' (Give an alignment point to Player)\n" .
#			"Usage: judge <player #> <0 (good) | 1 (bad)>\n";
#	} elsif ($playersID[$arg1] eq "") {
#		error	"Error in function 'judge' (Give an alignment point to Player)\n" .
#			"Player $arg1 does not exist.\n";
#	} else {
#		$arg2 = ($arg2 >= 1);
#		sendAlignment($net, $playersID[$arg1], $arg2);
#	}
#}

sub cmdKill {
	my (undef, $ID) = @_;

	my $target = $playersID[$ID];
	unless ($target) {
		error TF("Player %s does not exist.\n", $ID);
		return;
	}

	attack($target);
}

sub cmdLook {
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^(\d+)/;
	my ($arg2) = $args =~ /^\d+ (\d+)$/;
	if ($arg1 eq "") {
		error T("Syntax Error in function 'look' (Look a Direction)\n" .
			"Usage: look <body dir> [<head dir>]\n");
	} else {
		look($arg1, $arg2);
	}
}

sub cmdLookPlayer {
	my (undef, $arg1) = @_;
	if ($arg1 eq "") {
		error T("Syntax Error in function 'lookp' (Look at Player)\n" .
			"Usage: lookp <player #>\n");
	} elsif (!$playersID[$arg1]) {
		error TF("Error in function 'lookp' (Look at Player)\n" .
			"'%s' is not a valid player number.\n", $arg1);
	} else {
		lookAtPosition($players{$playersID[$arg1]}{pos_to});
	}
}

sub cmdManualMove {
	my ($switch, $steps) = @_;
	if (!$steps) {
		$steps = 5; 
	} elsif ($steps !~ /^\d+$/) {
		error TF("Error in function '%s' (Manual Move)\n" .
			"Usage: %s [distance]\n", $switch, $switch);
		return;
	}
	if ($switch eq "east") {
		manualMove($steps, 0);
	} elsif ($switch eq "west") {
		manualMove(-$steps, 0);
	} elsif ($switch eq "north") {
		manualMove(0, $steps);
	} elsif ($switch eq "south") {
		manualMove(0, -$steps);
	} elsif ($switch eq "northeast") {
		manualMove($steps, $steps);
	} elsif ($switch eq "southwest") {
		manualMove(-$steps, -$steps);
	} elsif ($switch eq "northwest") {
		manualMove(-$steps, $steps);
	} elsif ($switch eq "southeast") {
		manualMove($steps, -$steps);
	}
}

sub cmdMemo {
	sendMemo($net);
}

sub cmdMonsterList {
	my ($dmgTo, $dmgFrom, $dist, $pos, $name, $monsters);
	message TF("-----------Monster List-----------\n" .
		"#   Name                        ID      DmgTo DmgFrom  Distance    Coordinates\n"),	"list";

	$monsters = $monstersList->getItems();
	foreach my $monster (@{$monsters}) {
		$dmgTo = ($monster->{dmgTo} ne "")
			? $monster->{dmgTo}
			: 0;
		$dmgFrom = ($monster->{dmgFrom} ne "")
			? $monster->{dmgFrom}
			: 0;
		$dist = distance($char->{pos_to}, $monster->{pos_to});
		$dist = sprintf("%.1f", $dist) if (index($dist, '.') > -1);
		$pos = '(' . $monster->{pos_to}{x} . ', ' . $monster->{pos_to}{y} . ')';
		$name = $monster->name;
		if ($name ne $monster->{name_given}) {
			$name .= '[' . $monster->{name_given} . ']';
		}

		message(swrite(
			"@<< @<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<< @<<<< @<<<<    @<<<<<      @<<<<<<<<<<",
			[$monster->{binID}, $name, $monster->{binType}, $dmgTo, $dmgFrom, $dist, $pos]),
			"list");
	}
	message("----------------------------------\n", "list");
}

sub cmdMove {
	my (undef, $args) = @_;
	my ($arg1, $arg2, $arg3) = $args =~ /^(\d+) (\d+)(.*?)$/;

	my $map;
	if ($arg1 eq "") {
		$map = $args;
	} else {
		$map = $arg3;
	}
	$map =~ s/\s//g;
	# FIXME: this should be integrated with the other numbers
	if ($args eq "0") {
		if ($portalsID[0]) {
			message TF("Move into portal number 0 (%s,%s)\n", 
				$portals{$portalsID[0]}{'pos'}{'x'}, $portals{$portalsID[0]}{'pos'}{'y'});
			main::ai_route($field{name}, $portals{$portalsID[0]}{'pos'}{'x'}, $portals{$portalsID[0]}{'pos'}{'y'}, attackOnRoute => 1, noSitAuto => 1);
		} else {
			error T("No portals exist.\n");
		}
	} elsif (($arg1 eq "" || $arg2 eq "") && !$map) {
		error T("Syntax Error in function 'move' (Move Player)\n" .
			"Usage: move <x> <y> &| <map>\n");
	} elsif ($map eq "stop") {
		AI::clear(qw/move route mapRoute/);
		message T("Stopped all movement\n"), "success";
	} else {
		AI::clear(qw/move route mapRoute/);
		$map = $field{name} if ($map eq "");
		if ($maps_lut{"${map}.rsw"}) {
			my ($x, $y);
			if ($arg2 ne "") {
				message TF("Calculating route to: %s(%s): %s, %s\n", 
					$maps_lut{$map.'.rsw'}, $map, $arg1, $arg2), "route";
				$x = $arg1;
				$y = $arg2;
			} else {
				message TF("Calculating route to: %s(%s)\n", 
					$maps_lut{$map.'.rsw'}, $map), "route";
			}
			main::ai_route($map, $x, $y,
				attackOnRoute => 1,
				noSitAuto => 1,
				notifyUponArrival => 1);
		} elsif ($map =~ /^\d$/) {
			if ($portalsID[$map]) {
				message TF("Move into portal number %s (%s,%s)\n", 
					$map, $portals{$portalsID[$map]}{'pos'}{'x'}, $portals{$portalsID[$map]}{'pos'}{'y'});
				main::ai_route($field{name}, $portals{$portalsID[$map]}{'pos'}{'x'}, $portals{$portalsID[$map]}{'pos'}{'y'}, attackOnRoute => 1, noSitAuto => 1);
			} else {
				error T("No portals exist.\n");
			}
		} else {
			error TF("Map %s does not exist\n", $map);
		}
	}
}

sub cmdNPCList {
	my (undef, $args) = @_;
	my @arg = parseArgs($args);
	my $msg = T("-----------NPC List-----------\n" .
		"#    Name                         Coordinates   ID\n");

	if ($arg[0] =~ /^\d+$/) {
		my $i = $arg[0];
		if (my $npc = $npcsList->get($i)) {
			my $pos = "($npc->{pos}{x}, $npc->{pos}{y})";
			$msg .= swrite(
				"@<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<   @<<<<<<<<",
				[$i, $npc->name, $pos, $npc->{nameID}]);
			$msg .= "---------------------------------\n";
			message $msg, "info";

		} else {
			error T("Syntax Error in function 'nl' (List NPCs)\n" .
				"Usage: nl [<npc #>]\n");
		}
		return;
	}

	my $npcs = $npcsList->getItems();
	foreach my $npc (@{$npcs}) {
		my $pos = "($npc->{pos}{x}, $npc->{pos}{y})";
		$msg .= swrite(
			"@<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<   @<<<<<<<<",
			[$npc->{binID}, $npc->name, $pos, $npc->{nameID}]);
	}
	$msg .= "---------------------------------\n";
	message $msg, "list";
}

sub cmdOpenShop {
	main::openShop();
}

sub cmdParty {
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^(\w*)/;
	my ($arg2) = $args =~ /^\w* (\d+)\b/;

	if ($arg1 eq "" && ( !$char->{'party'} || !%{$char->{'party'}} )) {
		error T("Error in function 'party' (Party Functions)\n" .
			"Can't list party - you're not in a party.\n");
	} elsif ($arg1 eq "") {
		message TF("----------Party-----------\n" .
			"%s\n" .
			"#      Name                  Map                    Online    HP\n", 
			$char->{'party'}{'name'}), "list";
		for (my $i = 0; $i < @partyUsersID; $i++) {
			next if ($partyUsersID[$i] eq "");
			my $coord_string = "";
			my $hp_string = "";
			my $name_string = $char->{'party'}{'users'}{$partyUsersID[$i]}{'name'};
			my $admin_string = ($char->{'party'}{'users'}{$partyUsersID[$i]}{'admin'}) ? "(A)" : "";
			my $online_string;
			my $map_string;

			if ($partyUsersID[$i] eq $accountID) {
				# Translation Comment: Is the party user on list online?
				$online_string = T("Yes");
				($map_string) = $field{name};
				$coord_string = $char->{'pos'}{'x'}. ", ".$char->{'pos'}{'y'};
				$hp_string = $char->{'hp'}."/".$char->{'hp_max'}
						." (".int($char->{'hp'}/$char->{'hp_max'} * 100)
						."%)";
			} else {
				$online_string = ($char->{'party'}{'users'}{$partyUsersID[$i]}{'online'}) ? T("Yes") : T("No");
				($map_string) = $char->{'party'}{'users'}{$partyUsersID[$i]}{'map'} =~ /([\s\S]*)\.gat/;
				$coord_string = $char->{'party'}{'users'}{$partyUsersID[$i]}{'pos'}{'x'}
					. ", ".$char->{'party'}{'users'}{$partyUsersID[$i]}{'pos'}{'y'}
					if ($char->{'party'}{'users'}{$partyUsersID[$i]}{'pos'}{'x'} ne ""
						&& $char->{'party'}{'users'}{$partyUsersID[$i]}{'online'});
				$hp_string = $char->{'party'}{'users'}{$partyUsersID[$i]}{'hp'}."/".$char->{'party'}{'users'}{$partyUsersID[$i]}{'hp_max'}
					." (".int($char->{'party'}{'users'}{$partyUsersID[$i]}{'hp'}/$char->{'party'}{'users'}{$partyUsersID[$i]}{'hp_max'} * 100)
					."%)" if ($char->{'party'}{'users'}{$partyUsersID[$i]}{'hp_max'} && $char->{'party'}{'users'}{$partyUsersID[$i]}{'online'});
			}
			message(swrite(
				"@< @<< @<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<< @<<<<<<< @<<       @<<<<<<<<<<<<<<<<<<",
				[$i, $admin_string, $name_string, $map_string, $coord_string, $online_string, $hp_string]),
				"list");
		}
		message("--------------------------\n", "list");

	} elsif ($arg1 eq "create") {
		my ($arg2) = $args =~ /^\w* ([\s\S]*)/;
		if ($arg2 eq "") {
			error T("Syntax Error in function 'party create' (Organize Party)\n" .
				"Usage: party create <party name>\n");
		} else {
			sendPartyOrganize($net, $arg2);
		}

	} elsif ($arg1 eq "join" && $arg2 ne "1" && $arg2 ne "0") {
		error T("Syntax Error in function 'party join' (Accept/Deny Party Join Request)\n" .
			"Usage: party join <flag>\n");
	} elsif ($arg1 eq "join" && $incomingParty{'ID'} eq "") {
		error T("Error in function 'party join' (Join/Request to Join Party)\n" .
			"Can't accept/deny party request - no incoming request.\n");
	} elsif ($arg1 eq "join") {
		sendPartyJoin($net, $incomingParty{'ID'}, $arg2);
		undef %incomingParty;

	} elsif ($arg1 eq "request" && ( !$char->{'party'} || !%{$char->{'party'}} )) {
		error T("Error in function 'party request' (Request to Join Party)\n" .
			"Can't request a join - you're not in a party.\n");
	} elsif ($arg1 eq "request" && $playersID[$arg2] eq "") {
		error TF("Error in function 'party request' (Request to Join Party)\n" .
			"Can't request to join party - player %s does not exist.\n", $arg2);
	} elsif ($arg1 eq "request") {
		sendPartyJoinRequest($net, $playersID[$arg2]);

	} elsif ($arg1 eq "leave" && (!$char->{'party'} || !%{$char->{'party'}} ) ) {
		error T("Error in function 'party leave' (Leave Party)\n" .
			"Can't leave party - you're not in a party.\n");
	} elsif ($arg1 eq "leave") {
		sendPartyLeave($net);


	} elsif ($arg1 eq "share" && ( !$char->{'party'} || !%{$char->{'party'}} )) {
		error T("Error in function 'party share' (Set Party Share EXP)\n" .
			"Can't set share - you're not in a party.\n");
	} elsif ($arg1 eq "share" && $arg2 ne "1" && $arg2 ne "0") {
		error T("Syntax Error in function 'party share' (Set Party Share EXP)\n" .
			"Usage: party share <flag>\n");
	} elsif ($arg1 eq "share") {
		sendPartyShareEXP($net, $arg2);


	} elsif ($arg1 eq "kick" && ( !$char->{'party'} || !%{$char->{'party'}} )) {
		error T("Error in function 'party kick' (Kick Party Member)\n" .
			"Can't kick member - you're not in a party.\n");
	} elsif ($arg1 eq "kick" && $arg2 eq "") {
		error T("Syntax Error in function 'party kick' (Kick Party Member)\n" . 
			"Usage: party kick <party member #>\n");
	} elsif ($arg1 eq "kick" && $partyUsersID[$arg2] eq "") {
		error TF("Error in function 'party kick' (Kick Party Member)\n" .
			"Can't kick member - member %s doesn't exist.\n", $arg2);
	} elsif ($arg1 eq "kick") {
		sendPartyKick($net, $partyUsersID[$arg2]
				,$char->{'party'}{'users'}{$partyUsersID[$arg2]}{'name'});
	} else {
		error T("Syntax Error in function 'party' (Party Management)\n" .
			"Usage: party [<create|join|request|leave|share|kick>]\n");
	}
}

sub cmdPartyChat {
	my (undef, $arg1) = @_;
	if ($arg1 eq "") {
		error T("Syntax Error in function 'p' (Party Chat)\n" .
			"Usage: p <message>\n");
	} else {
		sendMessage($net, "p", $arg1);
	}
}

sub cmdPecopeco {
	my (undef, $arg1) = @_;

	if ($arg1 eq "") {
		if (hasPecopeco()) {
			message T("Your Pecopeco is active");
		} else {
			message T("Your Pecopeco is inactive");			
		}
	} elsif ($arg1 eq "release") {
		if (!hasPecopeco()) {
		error T("Error in function 'pecopeco release' (Remove Pecopeco Status)\n" .
			"You don't possess a Pecopeco.\n");
		} else {
			sendCompanionRelease();
		}
	}
}

sub cmdPet {
	my (undef, $subcmd) = @_;
	if (!%pet) {
		error T("Error in function 'pet' (Pet Management)\n" .
			"You don't have a pet.\n");

	} elsif ($subcmd eq "s" || $subcmd eq "status") {
		message TF("-----------Pet Status-----------\nName: %-23s Accessory: %s", $pet{name}, itemNameSimple($pet{accessory})), "list";

	} elsif ($subcmd eq "p" || $subcmd eq "performance") {
		sendPetPerformance($net);

	} elsif ($subcmd eq "r" || $subcmd eq "return") {
		sendPetReturnToEgg($net);

	} elsif ($subcmd eq "u" || $subcmd eq "unequip") {
		sendPetUnequipItem($net);
	}
}

sub cmdPetList {
	message T("-----------Pet List-----------\n" .
		"#    Type                     Name\n"), "list";
	for (my $i = 0; $i < @petsID; $i++) {
		next if ($petsID[$i] eq "");
		message(swrite(
			"@<<< @<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<",
			[$i, $pets{$petsID[$i]}{'name'}, $pets{$petsID[$i]}{'name_given'}]),
			"list");
	}
	message("----------------------------------\n", "list");
}

sub cmdPlayerList {
	my (undef, $args) = @_;
	my $msg;

	if ($args ne "") {
		my Actor::Player $player = Match::player($args);
		if (!$player) {
			error TF("Player \"%s\" does not exist.\n", $args);
			return;
		}

		my $ID = $player->{ID};
		my $body = $player->{look}{body} % 8;
		my $head = $player->{look}{head};
		if ($head == 0) {
			$head = $body;
		} elsif ($head == 1) {
			$head = $body - 1;
		} else {
			$head = $body + 1;
		}

		my $pos = calcPosition($player);
		my $mypos = calcPosition($char);
		my $dist = sprintf("%.1f", distance($pos, $mypos));
		$dist =~ s/\.0$//;

		my %vecPlayerToYou;
		my %vecYouToPlayer;
		getVector(\%vecPlayerToYou, $mypos, $pos);
		getVector(\%vecYouToPlayer, $pos, $mypos);
		my $degPlayerToYou = vectorToDegree(\%vecPlayerToYou);
		my $degYouToPlayer = vectorToDegree(\%vecYouToPlayer);
		my $hex = getHex($ID);
		my $playerToYou = int(sprintf("%.0f", (360 - $degPlayerToYou) / 45)) % 8;
		my $youToPlayer = int(sprintf("%.0f", (360 - $degYouToPlayer) / 45)) % 8;
		my $headTop = headgearName($player->{headgear}{top});
		my $headMid = headgearName($player->{headgear}{mid});
		my $headLow = headgearName($player->{headgear}{low});

		$msg = TF("------------------ Player Info ------------------\n" .
			"%s (%d)\n" .
			"Account ID: %s (Hex: %s)\n" .
			"Party: %s\n" .
			"Guild: %s\n" .
			"Position: %s, %s (%s of you: %s degrees)\n" .
			"Level: %-7d Distance: %-17s\n" .
			"Sex: %-6s    Class: %s\n" .
			"-------------------------------------------------\n" .
			"Body direction: %-19s Head direction:  %-19s\n" .
			"Weapon: %s\n" .
			"Shield: %s\n" .
			"Shoes : %s\n" .
			"Upper headgear: %-19s Middle headgear: %-19s\n" .
			"Lower headgear: %-19s Hair color:      %-19s\n" .
			"Walk speed: %s secs per block\n", 
		$player->name, $player->{binID}, $player->{nameID}, $hex, 
		($player->{party} && $player->{party}{name} ne '') ? $player->{party}{name} : '',
		($player->{guild}) ? $player->{guild}{name} : '',
		$pos->{x}, $pos->{y}, $directions_lut{$youToPlayer}, int($degYouToPlayer),
		$player->{lv}, $dist, $sex_lut{$player->{sex}}, $jobs_lut{$player->{jobID}},
		"$directions_lut{$body} ($body)", "$directions_lut{$head} ($head)",
		itemName({nameID => $player->{weapon}}),
		itemName({nameID => $player->{shield}}),
		itemName({nameID => $player->{shoes}}), $headTop, $headMid, 
			  $headLow, "$haircolors{$player->{hair_color}} ($player->{hair_color})",
			  $player->{walk_speed});
		
		
		if ($player->{dead}) {
			$msg .= T("Player is dead.\n");
		} elsif ($player->{sitting}) {
			$msg .= T("Player is sitting.\n");
		}

		if ($degPlayerToYou >= $head * 45 - 29 && $degPlayerToYou <= $head * 45 + 29) {
			$msg .= T("Player is facing towards you.\n");
		}

		$msg .= "-------------------------------------------------\n";
		message $msg, "info";
		return;
	}

	$msg =  T("-----------Player List-----------\n" .
		"#    Name                                Sex   Lv  Job         Dist  Coord\n");
	foreach my Actor::Player $player (@{$playersList->getItems()}) {
		my ($name, $dist, $pos);
		$name = $player->name;
		if ($player->{guild} && %{$player->{guild}}) {
			$name .= " [$player->{guild}{name}]";
		}
		$dist = distance($char->{pos_to}, $player->{pos_to});
		$dist = sprintf("%.1f", $dist) if (index ($dist, '.') > -1);
		$pos = '(' . $player->{pos_to}{x} . ', ' . $player->{pos_to}{y} . ')';

		$msg .= swrite(
			"@<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<< @<< @<<<<<<<<<< @<<<< @<<<<<<<<<<",
			[$player->{binID}, $name, $sex_lut{$player->{sex}}, $player->{lv}, $player->job, $dist, $pos]);
	}
	$msg .= "---------------------------------\n";
	message($msg, "list");
}

sub cmdPlayerSkill {
	my $switch = shift;
	my $last_arg_pos;
	my @args = parseArgs(shift, undef, undef, \$last_arg_pos);
	my $mode = shift;

	if ($mode eq 'c') {
		# Completion mode
		my $arg = $args[$#args];
		my @matches;

		if (@args == 2) {
			# Complete skill name
			@matches = Skills::complete($arg);
		} elsif (@args == 3) {
			# Complete player name
			@matches = completePlayerName($arg);
		}

		return ($last_arg_pos, \@matches);
	}

	if (@args < 1) {
		error T("Syntax Error in function 'sp' (Use Skill on Player)\n" .
			"Usage: sp (skill # or name) [player # or name] [level]\n");
		return;
	}

	my $skill = new Skills(auto => $args[0]);
	my $target;
	my $targetID;
	my $char_skill = $char->{skills}{$skill->handle};
	my $lv = $args[2] || $char_skill->{lv} || 10;

	if (!defined $skill->id) {
		error TF("Error in function 'sp' (Use Skill on Player)\n" .
			"'%s' is not a valid skill.\n", $args[0]);
		return;
	}

	if ($args[1] ne "") {
		$target = Match::player($args[1], 1);
		if (!$target) {
			error TF("Error in function 'sp' (Use Skill on Player)\n" .
				"Player '%s' does not exist.\n", $args[1]);
			return;
		}
		$targetID = $target->{ID};
	} else {
		$target = $char;
		$targetID = $accountID;
	}

	if (main::ai_getSkillUseType($skill->handle)) {
		main::ai_skillUse($skill->handle, $lv, 0, 0,
			$target->{pos_to}{x}, $target->{pos_to}{y});
	} else {
		main::ai_skillUse($skill->handle, $lv, 0, 0, $targetID);
	}
}

sub cmdPlugin {
	my (undef, $input) = @_;
	my @args = split(/ +/, $input, 2);

	if (@args == 0) {
		message T("--------- Currently loaded plugins ---------\n" .
			"#   Name              Description\n"), "list";
		my $i = 0;
		foreach my $plugin (@Plugins::plugins) {
			next unless $plugin;
			message(swrite(
				"@<< @<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<",
				[$i, $plugin->{name}, $plugin->{description}]
			), "list");
			$i++;
		}
		message("--------------------------------------------\n", "list");

	} elsif ($args[0] eq 'reload') {
		my @names;

		if ($args[1] =~ /^\d+$/) {
			push @names, $Plugins::plugins[$args[1]]{name};

		} elsif ($args[1] eq '') {
			error T("Syntax Error in function 'plugin reload' (Reload Plugin)\n" .
				"Usage: plugin reload <plugin name|plugin number#|\"all\">\n");
			return;

		} elsif ($args[1] eq 'all') {
			foreach my $plugin (@Plugins::plugins) {
				push @names, $plugin->{name};
			}

		} else {
			foreach my $plugin (@Plugins::plugins) {
				if ($plugin->{name} =~ /$args[1]/i) {
					push @names, $plugin->{name};
				}
			}
			if (!@names) {
				error T("Error in function 'plugin reload' (Reload Plugin)\n" .
					"The specified plugin names do not exist.\n");
				return;
			}
		}

		foreach (my $i = 0; $i < @names; $i++) {
			Plugins::reload($names[$i]);
		}

	} elsif ($args[0] eq 'load') {
		if ($args[1] eq '') {
			error T("Syntax Error in function 'plugin load' (Load Plugin)\n" .
				"Usage: plugin load <filename|\"all\">\n");
			return;
		} elsif ($args[1] eq 'all') {
			Plugins::loadAll();
		} else {
			Plugins::load($args[1]);
		}

	} elsif ($args[0] eq 'unload') {
		if ($args[1] =~ /^\d+$/) {
			if ($Plugins::plugins[$args[1]]) {
				my $name = $Plugins::plugins[$args[1]]{name};
				Plugins::unload($name);
				message TF("Plugin %s unloaded.\n", $name), "system";
			} else {
				error TF("'%s' is not a valid plugin number.\n", $args[1]);
			}

		} elsif ($args[1] eq '') {
			error T("Syntax Error in function 'plugin unload' (Unload Plugin)\n" .
				"Usage: plugin unload <plugin name|plugin number#|\"all\">\n");
			return;

		} elsif ($args[1] eq 'all') {
			Plugins::unloadAll();

		} else {
			foreach my $plugin (@Plugins::plugins) {
				if ($plugin->{name} =~ /$args[1]/i) {
					my $name = $plugin->{name};
					Plugins::unload($name);
					message TF("Plugin %s unloaded.\n", $name), "system";
				}
			}
		}

	} else {
		my $msg;
		$msg = T("--------------- Plugin command syntax ---------------\n" .
			"Command:                                              Description:\n" .
			" plugin                                                List loaded plugins\n" .
			" plugin load <filename>                                Load a plugin\n" .
			" plugin unload <plugin name|plugin number#|\"all\">      Unload a loaded plugin\n" .
			" plugin reload <plugin name|plugin number#|\"all\">      Reload a loaded plugin\n" .
			"-----------------------------------------------------\n");
		if ($args[0] eq 'help') {
			message($msg, "info");
		} else {
			error T("Syntax Error in function 'plugin' (Control Plugins)\n");
			error($msg);
		}
	}
}

sub cmdPMList {
	message T("-----------PM List-----------\n"), "list";
	for (my $i = 1; $i <= @privMsgUsers; $i++) {
		message(swrite(
			"@<<< @<<<<<<<<<<<<<<<<<<<<<<<",
			[$i, $privMsgUsers[$i - 1]]),
			"list");
	}
	message("-----------------------------\n", "list");
}

sub cmdPortalList {
	my (undef, $args) = @_;
	my ($arg) = parseArgs($args,1);
	if ($arg eq '') {
		message T("-----------Portal List-----------\n" .
			"#    Name                                Coordinates\n"), "list";
		for (my $i = 0; $i < @portalsID; $i++) {
			next if $portalsID[$i] eq "";
			my $portal = $portals{$portalsID[$i]};
			my $coords = "($portal->{pos}{x}, $portal->{pos}{y})";
			message(swrite(
				"@<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<",
				[$i, $portal->{name}, $coords]),
				"list");
		}
		message("---------------------------------\n", "list");
	} elsif ($arg eq 'recompile') {
		Settings::parseReload("portals");
		Misc::compilePortals() if Misc::compilePortals_check();
	}
}

sub cmdPrivateMessage {
	my ($switch, $args) = @_;
	my ($user, $msg) = parseArgs($args, 2);

	if ($user eq "" || $msg eq "") {
		error T("Syntax Error in function 'pm' (Private Message)\n" .
			"Usage: pm (username) (message)\n       pm (<#>) (message)\n");
		return;

	} elsif ($user =~ /^\d+$/) {
		if ($user - 1 >= @privMsgUsers) {
			error TF("Error in function 'pm' (Private Message)\n" .
				"Quick look-up %s does not exist\n", $user);
		} elsif (!@privMsgUsers) {
			error T("Error in function 'pm' (Private Message)\n" .
				"You have not pm-ed anyone before\n");
		} else {
			sendMessage($net, "pm", $msg, $privMsgUsers[$user - 1]);
			$lastpm{msg} = $msg;
			$lastpm{user} = $privMsgUsers[$user - 1];
		}

	} else {
		if (!defined binFind(\@privMsgUsers, $user)) {
			push @privMsgUsers, $user;
		}
		sendMessage($net, "pm", $msg, $user);
		$lastpm{msg} = $msg;
		$lastpm{user} = $user;
	}
}

sub cmdQuit {
	quit();
}

sub cmdReload {
	my (undef, $args) = @_;
	if ($args eq '') {
		error T("Syntax Error in function 'reload' (Reload Configuration Files)\n" .
			"Usage: reload <name|\"all\">\n");

	} else {
		Settings::parseReload($args);
		Log::initLogFiles();
	}
}

sub cmdReloadCode {
	my (undef, $args) = @_;
	if ($args ne "") {
		Modules::reload($args, 1);

	} else {
		Modules::reloadFile('functions.pl');
	}
}

sub cmdRelog {
	my (undef, $arg) = @_;
	if (!$arg || $arg =~ /^\d+$/) {
		relog($arg);
	} else {
		error T("Syntax Error in function 'relog' (Log out then log in.)\n" .
			"Usage: relog [delay]\n");
	}
}

sub cmdRepair {
	my (undef, $args) = @_;
	if ($args =~ /^\d+$/) {
		sendRepairItem($args);
	} else {
		error T("Syntax Error in function 'repair' (Repair player's items.)\n" .
			"Usage: repair [item number]\n");
	}
}

sub cmdRespawn {
	if ($char->{dead}) {
		sendRespawn($net);
	} else {
		main::useTeleport(2);
	}
}

sub cmdSell {
	my @args = parseArgs($_[1]);

	if ($args[0] eq "" && $talk{buyOrSell}) {
		sendGetSellList($net, $talk{ID});

	} elsif ($args[0] eq "list") {
		if (@sellList == 0) {
			message T("Your sell list is empty.\n"), "info";
		} else {
			my $text = '';
			$text .= T("------------- Sell list -------------\n" .
				"#   Item                           Amount\n");
			foreach my $item (@sellList) {
				$text .= sprintf("%-3d %-30s %d\n", $item->{invIndex}, $item->{name}, $item->{amount});
			}
			$text .= "-------------------------------------\n";
			message($text, "list");
		}

	} elsif ($args[0] eq "done") {
		sendSellBulk($net, \@sellList);
		message TF("Sold %s items.\n", @sellList.""), "success";
		@sellList = ();

	} elsif ($args[0] eq "cancel") {
		@sellList = ();
		message T("Sell list has been cleared.\n"), "info";

	} elsif ($args[0] eq "" || ($args[0] !~ /^\d+$/ && $args[0] !~ /[,\-]/)) {
		error T("Syntax Error in function 'sell' (Sell Inventory Item)\n" .
			"Usage: sell <inventory item index #> [<amount>]\n" .
			"       sell list\n" .
			"       sell done\n" .
			"       sell cancel\n");

	} else {
		my @items = Actor::Item::getMultiple($args[0]);
		if (@items > 0) {
			foreach my $item (@items) {
				my %obj;

				if (defined(findIndex(\@sellList, "invIndex", $item->{invIndex}))) {
					error TF("%s (%s) is already in the sell list.\n", $item->nameString, $item->{invIndex});
					next;
				}

				$obj{name} = $item->nameString();
				$obj{index} = $item->{index};
				$obj{invIndex} = $item->{invIndex};
				if (!$args[1] || $args[1] > $item->{amount}) {
					$obj{amount} = $item->{amount};
				} else {
					$obj{amount} = $args[1];
				}
				push @sellList, \%obj;
				message TF("Added to sell list: %s (%s) x %s\n", $obj{name}, $obj{invIndex}, $obj{amount}), "info";
			}
			message T("Type 'sell done' to sell everything in your sell list.\n"), "info";

		} else {
			error TF("Error in function 'sell' (Sell Inventory Item)\n" .
				"'%s' is not a valid item index #; no item has been added to the sell list.\n", 
				$args[0]);
		}
	}
}

sub cmdSendRaw {
	my (undef, $args) = @_;
	sendRaw($net, $args);
}

sub cmdShopInfoSelf {
	if (!$shopstarted) {
		error T("You do not have a shop open.\n");
		return;
	}
	# FIXME: Read the packet the server sends us to determine
	# the shop title instead of using $shop{title}.
	message TF("%s\n" .
		"#  Name                                     Type         Qty       Price   Sold\n",
		center(" $shop{title} ", 79, '-')), "list";

	my $priceAfterSale=0;
	my $i = 1;
	for my $item (@articles) {
		next unless $item;
		message(swrite(
			"@< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<< @>>> @>>>>>>>>>z @>>>>>",
			[$i++, $item->{name}, $itemTypes_lut{$item->{type}}, $item->{quantity}, formatNumber($item->{price}), $item->{sold}]),
			"list");
		$priceAfterSale += ($item->{quantity} * $item->{price});
	}
	message TF("%s\n" .
		"You have earned: %sz.\n" .
		"Current zeny:    %sz.\n" .
		"Maximum earned:  %sz.\n" .
		"Maximum zeny:    %sz.\n",
		('-'x79), formatNumber($shopEarned), formatNumber($char->{zenny}), 
		formatNumber($priceAfterSale), formatNumber($priceAfterSale + $char->{zenny})), "list";
}

sub cmdSit {
	$ai_v{sitAuto_forcedBySitCommand} = 1;
	AI::clear("move", "route", "mapRoute");
	AI::clear("attack") unless ai_getAggressives();
	main::sit();
	$ai_v{sitAuto_forceStop} = 0;
}

sub cmdSkills {
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^(\w+)/;
	my ($arg2) = $args =~ /^\w+ (\d+)/;
	if ($arg1 eq "") {
		my $msg = T("----------Skill List-----------\n" .
			"   # Skill Name                     Lv      SP\n");
		for my $handle (@skillsID) {
			my $skill = Skills->new(handle => $handle);
			my $sp = $char->{skills}{$handle}{sp} || '';
			$msg .= swrite(
				"@>>> @<<<<<<<<<<<<<<<<<<<<<<<<<<<< @>>    @>>>",
				[$skill->id, $skill->name, $char->{skills}{$handle}{lv}, $sp]);
		}
		$msg .= TF("\nSkill Points: %d\n", $char->{points_skill});
		$msg .= "-------------------------------\n";
		message($msg, "list");

	} elsif ($arg1 eq "add" && $arg2 =~ /\d+/) {
		my $skill = Skills->new(id => $arg2);
		if (!$skill->id || !$char->{skills}{$skill->handle}) {
			error TF("Error in function 'skills add' (Add Skill Point)\n" .
				"Skill %s does not exist.\n", $arg2);
		} elsif ($char->{points_skill} < 1) {
			error TF("Error in function 'skills add' (Add Skill Point)\n" .
				"Not enough skill points to increase %s\n", $skill->name);
		} else {
			sendAddSkillPoint($net, $skill->id);
		}

	} elsif ($arg1 eq "desc" && $arg2 =~ /\d+/) {
		my $skill = Skills->new(id => $arg2);
		if (!$skill->id) {
			error TF("Error in function 'skills desc' (Skill Description)\n" .
				"Skill %s does not exist.\n", $arg2);
		} else {
			my $description = $skillsDesc_lut{$skill->handle} || T("Error: No description available.\n");
			message TF("===============Skill Description===============\n" .
				"Skill: %s\n\n", $skill->name), "info";
			message $description, "info";
			message "==============================================\n", "info";
		}
	} else {
		error T("Syntax Error in function 'skills' (Skills Functions)\n" .
			"Usage: skills [<add | desc>] [<skill #>]\n");
	}
}

sub cmdSpells {
	message T("-----------Area Effects List-----------\n" .
		"  # Type                 Source                   X   Y\n"), "list";
	for my $ID (@spellsID) {
		my $spell = $spells{$ID};
		next unless $spell;

		message sprintf("%3d %-20s %-20s   %3d %3d\n", $spell->{binID}, getSpellName($spell->{type}), main::getActorName($spell->{sourceID}), $spell->{pos}{x}, $spell->{pos}{y}), "list";
	}
	message "---------------------------------------\n", "list";
}

sub cmdStand {
	delete $ai_v{sitAuto_forcedBySitCommand};
	$ai_v{sitAuto_forceStop} = 1;
	main::stand();
}

sub cmdStatAdd {
	# Add status point
	my (undef, $arg) = @_;
	if ($arg ne "str" && $arg ne "agi" && $arg ne "vit" && $arg ne "int"
	 && $arg ne "dex" && $arg ne "luk") {
		error T("Syntax Error in function 'stat_add' (Add Status Point)\n" .
			"Usage: stat_add <str | agi | vit | int | dex | luk>\n");

	} elsif ($char->{'$arg'} >= 99 && !$config{statsAdd_over_99}) {
		error T("Error in function 'stat_add' (Add Status Point)\n" .
			"You cannot add more stat points than 99\n");

	} elsif ($char->{"points_$arg"} > $char->{'points_free'}) {
		error TF("Error in function 'stat_add' (Add Status Point)\n" .
			"Not enough status points to increase %s\n", $arg);

	} else {
		my $ID;
		if ($arg eq "str") {
			$ID = 0x0D;
		} elsif ($arg eq "agi") {
			$ID = 0x0E;
		} elsif ($arg eq "vit") {
			$ID = 0x0F;
		} elsif ($arg eq "int") {
			$ID = 0x10;
		} elsif ($arg eq "dex") {
			$ID = 0x11;
		} elsif ($arg eq "luk") {
			$ID = 0x12;
		}

		$char->{$arg} += 1;
		sendAddStatusPoint($net, $ID);
	}
}

sub cmdStats {
	my $msg = swrite(TF(
		"---------- Char Stats ----------\n" .
		"Str: \@<<+\@<< #\@< Atk:  \@<<+\@<< Def:  \@<<+\@<<\n" .
		"Agi: \@<<+\@<< #\@< Matk: \@<<\@\@<< Mdef: \@<<+\@<<\n" .
		"Vit: \@<<+\@<< #\@< Hit:  \@<<     Flee: \@<<+\@<<\n" .
		"Int: \@<<+\@<< #\@< Critical: \@<< Aspd: \@<<\n" .
		"Dex: \@<<+\@<< #\@< Status Points: \@<<<\n" .
		"Luk: \@<<+\@<< #\@< Guild: \@<<<<<<<<<<<<<<<<<<<<<\n" .
		"--------------------------------\n" .
		"Hair color: \@<<<<<<<<<<<<<<<<<\n" .
		"Walk speed: %.2f secs per block\n" .
		"--------------------------------", $char->{walk_speed}),	
	[$char->{'str'}, $char->{'str_bonus'}, $char->{'points_str'}, $char->{'attack'}, $char->{'attack_bonus'}, $char->{'def'}, $char->{'def_bonus'},
	$char->{'agi'}, $char->{'agi_bonus'}, $char->{'points_agi'}, $char->{'attack_magic_min'}, '~', $char->{'attack_magic_max'}, $char->{'def_magic'}, $char->{'def_magic_bonus'},
	$char->{'vit'}, $char->{'vit_bonus'}, $char->{'points_vit'}, $char->{'hit'}, $char->{'flee'}, $char->{'flee_bonus'},
	$char->{'int'}, $char->{'int_bonus'}, $char->{'points_int'}, $char->{'critical'}, $char->{'attack_speed'},
	$char->{'dex'}, $char->{'dex_bonus'}, $char->{'points_dex'}, $char->{'points_free'},
	$char->{'luk'}, $char->{'luk_bonus'}, $char->{'points_luk'}, $char->{guild} ? $char->{guild}{name} : T("None"),
	"$haircolors{$char->{hair_color}} ($char->{hair_color})"]);
	
	$msg .= T("You are sitting.\n") if ($char->{sitting});

	message $msg, "info";
}

sub cmdStatus {
	# Display character status
	my $msg;
	my ($baseEXPKill, $jobEXPKill);

	if ($char->{'exp_last'} > $char->{'exp'}) {
		$baseEXPKill = $char->{'exp_max_last'} - $char->{'exp_last'} + $char->{'exp'};
	} elsif ($char->{'exp_last'} == 0 && $char->{'exp_max_last'} == 0) {
		$baseEXPKill = 0;
	} else {
		$baseEXPKill = $char->{'exp'} - $char->{'exp_last'};
	}
	if ($char->{'exp_job_last'} > $char->{'exp_job'}) {
		$jobEXPKill = $char->{'exp_job_max_last'} - $char->{'exp_job_last'} + $char->{'exp_job'};
	} elsif ($char->{'exp_job_last'} == 0 && $char->{'exp_job_max_last'} == 0) {
		$jobEXPKill = 0;
	} else {
		$jobEXPKill = $char->{'exp_job'} - $char->{'exp_job_last'};
	}


	my ($hp_string, $sp_string, $base_string, $job_string, $weight_string, $job_name_string, $zeny_string);

	$hp_string = $char->{'hp'}."/".$char->{'hp_max'}." ("
		.int($char->{'hp'}/$char->{'hp_max'} * 100)
		."%)" if $char->{'hp_max'};
	$sp_string = $char->{'sp'}."/".$char->{'sp_max'}." ("
		.int($char->{'sp'}/$char->{'sp_max'} * 100)
		."%)" if $char->{'sp_max'};
	$base_string = formatNumber($char->{'exp'})."/".formatNumber($char->{'exp_max'})." /$baseEXPKill ("
			.sprintf("%.2f",$char->{'exp'}/$char->{'exp_max'} * 100)
			."%)"
			if $char->{'exp_max'};
	$job_string = formatNumber($char->{'exp_job'})."/".formatNumber($char->{'exp_job_max'})." /$jobEXPKill ("
			.sprintf("%.2f",$char->{'exp_job'}/$char->{'exp_job_max'} * 100)
			."%)"
			if $char->{'exp_job_max'};
	$weight_string = $char->{'weight'}."/".$char->{'weight_max'} .
			" (" . sprintf("%.1f", $char->{'weight'}/$char->{'weight_max'} * 100)
			. "%)"
			if $char->{'weight_max'};
	$job_name_string = "$jobs_lut{$char->{'jobID'}} $sex_lut{$char->{'sex'}}";
	$zeny_string = formatNumber($char->{'zenny'}) if (defined($char->{'zenny'}));

	# Translation Comment: No status effect on player		
	my $statuses = 'none';
	if (defined $char->{statuses} && %{$char->{statuses}}) {
		$statuses = join(", ", keys %{$char->{statuses}});
	}

	my $dmgpsec_string = sprintf("%.2f", $dmgpsec);
	my $totalelasped_string = sprintf("%.2f", $totalelasped);
	my $elasped_string = sprintf("%.2f", $elasped);
	
	$msg = swrite(
		TF("----------------------- Status -------------------------\n" .
		"\@<<<<<<<<<<<<<<<<<<<<<<<         HP: \@>>>>>>>>>>>>>>>>>>\n" .
		"\@<<<<<<<<<<<<<<<<<<<<<<<         SP: \@>>>>>>>>>>>>>>>>>>\n" .
		"Base: \@<<    \@>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\n" .
		"Job : \@<<    \@>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\n" .
		"Zeny: \@<<<<<<<<<<<<<<<<<     Weight: \@>>>>>>>>>>>>>>>>>>\n" .
		"Statuses: %s\n" .
		"Spirits: %s\n" .
		"--------------------------------------------------------\n" .
		"Total Damage: \@>>>>>>>>>>>>> Dmg/sec: \@<<<<<<<<<<<<<<\n" .
		"Total Time spent (sec): \@>>>>>>>>\n" .
		"Last Monster took (sec): \@>>>>>>>\n" .
		"--------------------------------------------------------",
		$statuses, (exists $char->{spirits} ? $char->{spirits} : 0)),
		[$char->{'name'}, $hp_string, $job_name_string, $sp_string,
		$char->{'lv'}, $base_string, $char->{'lv_job'}, $job_string, $zeny_string, $weight_string,
		$totaldmg, $dmgpsec_string, $totalelasped_string, $elasped_string]);
		
	message($msg, "info");
}

sub cmdStorage {
	if ($storage{opened}) {
		my (undef, $args) = @_;

		my ($switch, $items) = split(' ', $args, 2);
		if (!$switch || $switch eq 'eq' || $switch eq 'u' || $switch eq 'nu') {
			cmdStorage_list($switch);
		} elsif ($switch eq 'add') {
			cmdStorage_add($items);
		} elsif ($switch eq 'addfromcart') {
			cmdStorage_addfromcart($items);
		} elsif ($switch eq 'get') {
			cmdStorage_get($items);
		} elsif ($switch eq 'gettocart') {
			cmdStorage_gettocart($items);
		} elsif ($switch eq 'close') {
			cmdStorage_close();
		} elsif ($switch eq 'log') {
			cmdStorage_log();
		} elsif ($switch eq 'desc') {
			cmdStorage_desc($items);
		} else {
			error T("Syntax Error in function 'storage' (Storage Functions)\n" .
				"Usage: storage [<eq|u|nu>]\n" .
				"       storage close\n" .
				"       storage add <inventory_item> [<amount>]\n" .
				"       storage addfromcart <cart_item> [<amount>]\n" . 
				"       storage get <storage_item> [<amount>]\n" . 
				"       storage gettocart <storage_item> [<amount>]\n" .
				"       storage desc <storage_item_#>\n".
				"       storage log");
		}
	} else {
		error T("No information about storage; it has not been opened before in this session\n");
	}
}

sub cmdStorage_list {
	my $type = shift;
	message "$type\n";
	
	my @useable;
	my @equipment;
	my @non_useable;
	
	for (my $i = 0; $i < @storageID; $i++) {
		next if ($storageID[$i] eq "");
		my $item = $storage{$storageID[$i]};
		if ($item->{type} == 3 ||
		    $item->{type} == 6 ||
		    $item->{type} == 10) {
			push @non_useable, $item;
		} elsif ($item->{type} <= 2) {
			push @useable, $item;
		} else {
			my %eqp;
			$eqp{binID} = $i;
			$eqp{name} = $item->{name};
			$eqp{type} = $itemTypes_lut{$item->{type}};
			$eqp{identified} = " -- " . T("Not Identified") if !$item->{identified};
			push @equipment, \%eqp;
		}
	}
	
	my $msg = T("-----------Storage-------------\n");
	
	if (!$type || $type eq 'eq') {
		$msg .= T("-- Equipment --\n");
		foreach my $item (@equipment) {
			$msg .= sprintf("%-3d  %s (%s) %s\n", $item->{binID}, $item->{name}, $item->{type}, $item->{identified});
		}
	}
	
	if (!$type || $type eq 'nu') {
		$msg .= T("-- Non-Usable --\n");
		for (my $i = 0; $i < @non_useable; $i++) {
			my $item = $non_useable[$i];
			my $binID = $item->{binID};
			my $display = $item->{name};
			$display .= " x $item->{amount}";
			$msg .= swrite(
				"@<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<",
				[$binID, $display]);
		}
	}
	
	if (!$type || $type eq 'u') {
		$msg .= T("-- Usable --\n");
		for (my $i = 0; $i < @useable; $i++) {
			my $item = $useable[$i];
			my $binID = $item->{binID};
			my $display = $item->{name};
			$display .= " x $item->{amount}";
			$msg .= swrite(
				"@<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<",
				[$binID, $display]);
		}
	}
	
	$msg .= "-------------------------------\n";
	$msg .= TF("Capacity: %d/%d\n", $storage{items}, $storage{items_max});
	$msg .= "-------------------------------\n";
	message($msg, "list");
}

sub cmdStorage_add {
	my $items = shift;

	my ($name, $amount) = $items =~ /^(.*?)(?: (\d+))?$/;
	my $item = Match::inventoryItem($name);
	if (!$item) {
		error TF("Inventory Item '%s' does not exist.\n", $name);
		return;
	}

	if ($item->{equipped}) {
		error TF("Inventory Item '%s' is equipped.\n", $name);
		return;
	}

	if (!defined($amount) || $amount > $item->{amount}) {
		$amount = $item->{amount};
	}
	sendStorageAdd($item->{index}, $amount);
}

sub cmdStorage_addfromcart {
	my $items = shift;

	my ($name, $amount) = $items =~ /^(.*?)(?: (\d+))?$/;
	my $item = Match::cartItem($name);
	if (!$item) {
		error TF("Cart Item '%s' does not exist.\n", $name);
		return;
	}

	if (!defined($amount) || $amount > $item->{amount}) {
		$amount = $item->{amount};
	}
	sendStorageAddFromCart($item->{index}, $amount);
}

sub cmdStorage_get {
	my $items = shift;

	my ($names, $amount) = $items =~ /^(.*?)(?: (\d+))?$/;
	my @names = split(',', $names);
	my @items;

	for my $name (@names) {
		if ($name =~ /^(\d+)\-(\d+)$/) {
			for my $i ($1..$2) {
				push @items, $storage{$storageID[$i]} if ($storage{$storageID[$i]});
			}

		} else {
			my $item = Match::storageItem($name);
			if (!$item) {
				error TF("Storage Item '%s' does not exist.\n", $name);
				next;
			}
			push @items, $item;
		}
	}

	storageGet(\@items, $amount) if @items;
}

sub cmdStorage_gettocart {
	my $items = shift;

	my ($names, $amount) = $items =~ /^(.*?)(?: (\d+))?$/;
	my @names = split(',', $names);
	my @items;

	for my $name (@names) {
		if ($name =~ /^(\d+)\-(\d+)$/) {
			for my $i ($1..$2) {
				push @items, $storage{$storageID[$i]} if ($storage{$storageID[$i]});
			}

		} else {
			my $item = Match::storageItem($name);
			if (!$item) {
				error TF("Storage Item '%s' does not exist.\n", $name);
				next;
			}
			push @items, $item;
		}
	}

	sendStorageGetToCart(\@items, $amount) if @items;
}

sub cmdStorage_close {
	sendStorageClose();
}

sub cmdStorage_log {
	writeStorageLog(1);
}

sub cmdStorage_desc {
	my $items = shift;
	my $item = Match::storageItem($items);
	if (!$item) {
		error TF("Error in function 'storage desc' (Show Storage Item Description)\n" .
			"Storage Item %s does not exist.\n", $items);
	} else {
		printItemDesc($item->{nameID});
	}
}

sub cmdStore {
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^(\w+)/;
	my ($arg2) = $args =~ /^\w+ (\d+)/;
	if ($arg1 eq "" && !$talk{'buyOrSell'}) {
		message T("----------Store List-----------\n" .
			"#  Name                    Type           Price\n"), "list";
		my $display;
		for (my $i = 0; $i < @storeList; $i++) {
			$display = $storeList[$i]{'name'};
			message(swrite(
				"@< @<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<< @>>>>>>>z",
				[$i, $display, $itemTypes_lut{$storeList[$i]{'type'}}, $storeList[$i]{'price'}]),
				"list");
		}
		message("-------------------------------\n", "list");
	} elsif ($arg1 eq "" && $talk{'buyOrSell'}) {
		sendGetStoreList($net, $talk{'ID'});

	} elsif ($arg1 eq "desc" && $arg2 =~ /\d+/ && !$storeList[$arg2]) {
		error TF("Error in function 'store desc' (Store Item Description)\n" .
			"Store item %s does not exist\n", $arg2);
	} elsif ($arg1 eq "desc" && $arg2 =~ /\d+/) {
		printItemDesc($storeList[$arg2]{nameID});

	} else {
		error T("Syntax Error in function 'store' (Store Functions)\n" .
			"Usage: store [<desc>] [<store item #>]\n");
	}
}

sub cmdSwitchConf {
	my (undef, $filename) = @_;
	if (!defined $filename) {
		error T("Syntax Error in function 'switchconf' (Switch Configuration File)\n" .
			"Usage: switchconf <filename>\n");
	} elsif (! -f $filename) {
		error TF("Syntax Error in function 'switchconf' (Switch Configuration File)\n" .
			"File %s does not exist.\n", $filename);
	} else {
		switchConfigFile($filename);
		message TF("Switched config file to \"%s\".\n", $filename), "system";
	}
}

sub cmdTake {
	my (undef, $arg1) = @_;
	if ($arg1 eq "") {
		error T("Syntax Error in function 'take' (Take Item)\n" .
			"Usage: take <item #>\n");
	} elsif ($arg1 eq "first" && scalar(keys(%items)) == 0) {
		error T("Error in function 'take first' (Take Item)\n" .
			"There are no items near.\n");
	} elsif ($arg1 eq "first") {
		my @keys = keys %items;
		AI::take($keys[0]);
	} elsif (!$itemsID[$arg1]) {
		error TF("Error in function 'take' (Take Item)\n" .
			"Item %s does not exist.\n", $arg1);
	} else {
		main::take($itemsID[$arg1]);
	}
}

sub cmdTalk {
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^(\w+)/;
	my ($arg2) = $args =~ /^\w+ (\d+)/;

	if ($arg1 =~ /^\d+$/ && $npcsID[$arg1] eq "") {
		error TF("Error in function 'talk' (Talk to NPC)\n" .
			"NPC %s does not exist\n", $arg1);
	} elsif ($arg1 =~ /^\d+$/) {
		sendTalk($net, $npcsID[$arg1]);

	} elsif (($arg1 eq "resp" || $arg1 eq "num" || $arg1 eq "text") && !%talk) {
		error TF("Error in function 'talk %s' (Respond to NPC)\n" .
			"You are not talking to any NPC.\n", $arg1);

	} elsif ($arg1 eq "resp" && $arg2 eq "") {
		if (!$talk{'responses'}) {
		error T("Error in function 'talk resp' (Respond to NPC)\n" .
			"No NPC response list available.\n");
			return;
		}
		my $display = $talk{name};
		message TF("----------Responses-----------\n" .
			"NPC: %s\n" .
			"#  Response\n", $display),"list";
		for (my $i = 0; $i < @{$talk{'responses'}}; $i++) {
			message(sprintf(
				"%2s %s\n",
				$i, $talk{'responses'}[$i]),
				"list");
		}
		message("-------------------------------\n", "list");

	} elsif ($arg1 eq "resp" && $arg2 ne "" && $talk{'responses'}[$arg2] eq "") {
		error TF("Error in function 'talk resp' (Respond to NPC)\n" .
			"Response %s does not exist.\n", $arg2);

	} elsif ($arg1 eq "resp" && $arg2 ne "") {
		if ($talk{'responses'}[$arg2] eq "Cancel Chat") {
			$arg2 = 255;
		} else {
			$arg2 += 1;
		}
		sendTalkResponse($net, $talk{'ID'}, $arg2);

	} elsif ($arg1 eq "num" && $arg2 eq "") {
		error T("Error in function 'talk num' (Respond to NPC)\n" .
			"You must specify a number.\n");

	} elsif ($arg1 eq "num" && !($arg2 =~ /^\d+$/)) {
		error TF("Error in function 'talk num' (Respond to NPC)\n" .
			"%s is not a valid number.\n", $arg2);

	} elsif ($arg1 eq "num" && $arg2 =~ /^\d+$/) {
		sendTalkNumber($net, $talk{'ID'}, $arg2);

	} elsif ($arg1 eq "text") {
		my ($arg2) = $args =~ /^\w+ (.*)/;
		if ($arg2 eq "") {
			error T("Error in function 'talk text' (Respond to NPC)\n" .
				"You must specify a string.\n");
		} else {
			sendTalkText($net, $talk{'ID'}, $arg2);
		}

	} elsif ($arg1 eq "cont" && !%talk) {
		error T("Error in function 'talk cont' (Continue Talking to NPC)\n" .
			"You are not talking to any NPC.\n");

	} elsif ($arg1 eq "cont") {
		sendTalkContinue($net, $talk{'ID'});

	} elsif ($arg1 eq "no") {
		if (!%talk) {
			error T("You are not talking to any NPC.\n");
		} else {
			sendTalkCancel($net, $talk{'ID'});
		}

	} else {
		error T("Syntax Error in function 'talk' (Talk to NPC)\n" .
			"Usage: talk <NPC # | cont | resp | num> [<response #>|<number #>]\n");
	}
}

sub cmdTalkNPC {
	my (undef, $args) = @_;

	my ($x, $y, $sequence) = $args =~ /^(\d+) (\d+) (.+)$/;
	unless (defined $x) {
		error T("Syntax Error in function 'talknpc' (Talk to an NPC)\n" .
			"Usage: talknpc <x> <y> <sequence>\n");
		return;
	}

	message TF("Talking to NPC at (%d, %d) using sequence: %s\n", $x, $y, $sequence);
	main::ai_talkNPC($x, $y, $sequence);
}

sub cmdTank {
	my (undef, $arg) = @_;
	$arg =~ s/ .*//;

	if ($arg eq "") {
		error T("Syntax Error in function 'tank' (Tank for a Player)\n" .
			"Usage: tank <player #|player name>\n");

	} elsif ($arg eq "stop") {
		configModify("tankMode", 0);

	} elsif ($arg =~ /^\d+$/) {
		if (!$playersID[$arg]) {
			error TF("Error in function 'tank' (Tank for a Player)\n" .
				"Player %s does not exist.\n", $arg);
		} else {
			configModify("tankMode", 1);
			configModify("tankModeTarget", $players{$playersID[$arg]}{name});
		}

	} else {
		my $found;
		foreach my $ID (@playersID) {
			next if !$ID;
			if (lc $players{$ID}{name} eq lc $arg) {
				$found = $ID;
				last;
			}
		}

		if ($found) {
			configModify("tankMode", 1);
			configModify("tankModeTarget", $players{$found}{name});
		} else {
			error TF("Error in function 'tank' (Tank for a Player)\n" .
				"Player %s does not exist.\n", $arg);
		}
	}
}

sub cmdTeleport {
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^(\d)/;
	$arg1 = 1 unless $arg1;
	main::useTeleport($arg1);
}

sub cmdTestShop {
	my @items = main::makeShop();
	return unless @items;

	message TF("%s\n" .
		"Name                                      Amount  Price\n", 
		center(" $shop{title} ", 79, '-')), "list";
	for my $item (@items) {
		message(sprintf("%-40s %7d %10s z\n", $item->{name}, 
			$item->{amount}, main::formatNumber($item->{price})), "list");
	}
	message("-------------------------------------------------------------------------------\n", "list");
	message TF("Total of %d items to sell.\n", binSize(\@items)), "list";
}

sub cmdTimeout {
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^(\w+)/;
	my ($arg2) = $args =~ /^\w+\s+([\s\S]+)\s*$/;
	if ($arg1 eq "") {
		error T("Syntax Error in function 'timeout' (set a timeout)\n" .
			"Usage: timeout <type> [<seconds>]\n");
	} elsif ($timeout{$arg1} eq "") {
		error TF("Error in function 'timeout' (set a timeout)\n" .
			"Timeout %s doesn't exist\n", $arg1);
	} elsif ($arg2 eq "") {
		message TF("Timeout '%s' is %s\n", 
			$arg1, $timeout{$arg1}{timeout}), "info";
	} else {
		setTimeout($arg1, $arg2);
	}
}

sub cmdUnequip {
	my (undef, $args) = @_;
	my ($arg1) = $args;

	if ($arg1 eq "") {
		error T("You must specify an item to unequip.\n");
		return;
	}

	my $item = Match::inventoryItem($arg1);

	if (!$item) {
		error TF("You don't have %s.\n", $arg1);
		return;
	}

	if (!$item->{equipped} && $item->{type} != 10) {
		error TF("Error in function 'unequip' (Unequip Inventory Item)\n" .
			"Inventory Item %s is not equipped.\n", $arg1);
		return;
	}
	sendUnequip($net, $item->{index});
}

sub cmdUseItemOnMonster {
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^(\d+)/;
	my ($arg2) = $args =~ /^\d+ (\d+)/;

	if ($arg1 eq "" || $arg2 eq "") {
		error T("Syntax Error in function 'im' (Use Item on Monster)\n" .
			"Usage: im <item #> <monster #>\n");
	} elsif (!$char->{'inventory'}[$arg1] || !%{$char->{'inventory'}[$arg1]}) {
		error TF("Error in function 'im' (Use Item on Monster)\n" .
			"Inventory Item %s does not exist.\n", $arg1);
	} elsif ($char->{'inventory'}[$arg1]{'type'} > 2) {
		error TF("Error in function 'im' (Use Item on Monster)\n" .
			"Inventory Item %s is not of type Usable.\n", $arg1);
	} elsif ($monstersID[$arg2] eq "") {
		error TF("Error in function 'im' (Use Item on Monster)\n" .
			"Monster %s does not exist.\n", $arg2);
	} else {
		$char->{'inventory'}[$arg1]->use($monstersID[$arg2]);
	}
}

sub cmdUseItemOnPlayer {
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^(\d+)/;
	my ($arg2) = $args =~ /^\d+ (\d+)/;
	if ($arg1 eq "" || $arg2 eq "") {
		error T("Syntax Error in function 'ip' (Use Item on Player)\n" .
			"Usage: ip <item #> <player #>\n");
	} elsif (!$char->{'inventory'}[$arg1] || !%{$char->{'inventory'}[$arg1]}) {
		error TF("Error in function 'ip' (Use Item on Player)\n" .
			"Inventory Item %s does not exist.\n", $arg1);
	} elsif ($char->{'inventory'}[$arg1]{'type'} > 2) {
		error TF("Error in function 'ip' (Use Item on Player)\n" .
			"Inventory Item %s is not of type Usable.\n", $arg1);
	} elsif ($playersID[$arg2] eq "") {
		error TF("Error in function 'ip' (Use Item on Player)\n" .
			"Player %s does not exist.\n", $arg2);
	} else {
		$char->{'inventory'}[$arg1]->use($playersID[$arg2]);
	}
}

sub cmdUseItemOnSelf {
	my (undef, $args) = @_;
	if ($args eq "") {
		error T("Syntax Error in function 'is' (Use Item on Yourself)\n" .
			"Usage: is <item>\n");
		return;
	}
	my $item = Actor::Item::get($args);
	if (!$item) {
		error TF("Error in function 'is' (Use Item on Yourself)\n" .
			"Inventory Item %s does not exist.\n", $args);
		return;
	}
	if ($item->{type} > 2) {
		error TF("Error in function 'is' (Use Item on Yourself)\n" .
			"Inventory Item %s is not of type Usable.\n", $item);
		return;
	}
	$item->use;
}

sub cmdUseSkill {
	my ($switch, $args) = @_;
	my ($skillID, $lv, $target, $targetNum, $targetID, $x, $y);

	# Resolve skill ID
	($skillID, $args) = split(/ /, $args, 2);
	my $skill = Skills->new(id => $skillID);
	if (!defined $skill->id) {
		error TF("Skill %s does not exist.\n", $skillID);
		return;
	}
	my $char_skill = $char->{skills}{$skill->handle};

	# Resolve skill level
	if ($switch eq 'sl') {
		($x, $y, $lv) = split(/ /, $args);
	} elsif ($switch eq "ss") {
		($lv) = split(/ /, $args);
	} else {
		($targetNum, $lv) = split(/ /, $args);
		if ($targetNum !~ /^\d+$/) {
			error TF("%s is not a number.\n", $targetNum);
			return;
		}
	}
	# Attempt to fill in unspecified skill level
	$lv ||= $char_skill->{lv};
	$lv ||= 10; # Server should fix excessively high skill level for us

	# Resolve target
	if ($switch eq 'sl') {
		if (!defined($x) || !defined($y)) {
			#error "(X, Y) coordinates not specified.\n";
			#return;
			my $pos = calcPosition($char);
			my @positions = calcRectArea($pos->{x}, $pos->{y}, int(rand 2) + 2);
			$pos = $positions[rand(@positions)];
			($x, $y) = ($pos->{x}, $pos->{y});
		}
	} elsif ($switch eq 'ss' || ($switch eq 'sp' && !defined($targetNum))) {
		$targetID = $accountID;
		$target = $char;
	} elsif ($switch eq 'sp') {
		$targetID = $playersID[$targetNum];
		if (!$targetID) {
			error TF("Player %d does not exist.\n", $targetNum);
			return;
		}
		$target = $players{$targetID};
	} elsif ($switch eq 'sm') {
		$targetID = $monstersID[$targetNum];
		if (!$targetID) {
			error TF("Monster %d does not exist.\n", $targetNum);
			return;
		}
		$target = $monsters{$targetID};
	} elsif ($switch eq 'ssp') {
		$targetID = $spellsID[$targetNum];
		if (!$targetID) {
			error TF("Spell %d does not exist.\n", $targetNum);
			return;
		}
		$target = $spells{$targetID};
	}

	# Resolve target location as necessary
	if (main::ai_getSkillUseType($skill->handle)) {
		if ($targetID) {
			$x = $target->{pos_to}{x};
			$y = $target->{pos_to}{y};
		}
		main::ai_skillUse($skill->handle, $lv, 0, 0, $x, $y);
	} else {
		main::ai_skillUse($skill->handle, $lv, 0, 0, $targetID);
	}
}

sub cmdVender {
	my (undef, $args) = @_;
	my ($arg1) = $args =~ /^([\d\w]+)/;
	my ($arg2) = $args =~ /^[\d\w]+ (\d+)/;
	my ($arg3) = $args =~ /^[\d\w]+ \d+ (\d+)/;
	if ($arg1 eq "") {
		error T("Syntax error in function 'vender' (Vender Shop)\n" .
			"Usage: vender <vender # | end> [<item #> <amount>]\n");
	} elsif ($arg1 eq "end") {
		undef @venderItemList;
		undef $venderID;
	} elsif ($venderListsID[$arg1] eq "") {
		error TF("Error in function 'vender' (Vender Shop)\n" .
			"Vender %s does not exist.\n", $arg1);
	} elsif ($arg2 eq "") {
		sendEnteringVender($net, $venderListsID[$arg1]);
	} elsif ($venderListsID[$arg1] ne $venderID) {
		error T("Error in function 'vender' (Vender Shop)\n" .
			"Vender ID is wrong.\n");
	} else {
		if ($arg3 <= 0) {
			$arg3 = 1;
		}
		sendBuyVender($net, $venderID, $arg2, $arg3);
	}
}

sub cmdVenderList {
	message T("-----------Vender List-----------\n" .
		"#   Title                                Coords     Owner\n"), "list";
	for (my $i = 0; $i < @venderListsID; $i++) {
		next if ($venderListsID[$i] eq "");
		my $player = Actor::get($venderListsID[$i]);
		# autovivifies $obj->{pos_to} but it doesnt matter
		message(sprintf(
			"%3d %-36s (%3s, %3s) %-20s\n",
			$i, $venderLists{$venderListsID[$i]}{'title'},
			$player->{pos_to}{x} || '?', $player->{pos_to}{y} || '?', $player->name),
			"list");
	}
	message("----------------------------------\n", "list");
}

sub cmdVerbose {
	if ($config{'verbose'}) {
		configModify("verbose", 0);
	} else {
		configModify("verbose", 1);
	}
}

sub cmdVersion {
	message "$Settings::versionText";
}

sub cmdWarp {
	my (undef, $map) = @_;

	if ($map eq '') {
		error T("Error in function 'warp' (Open/List Warp Portal)\n" .
			"Usage: warp <map name | map number# | list>\n");

	} elsif ($map =~ /^\d+$/) {
		if (!$char->{warp}{memo} || !@{$char->{warp}{memo}}) {
			error T("You didn't cast warp portal.\n");
			return;
		}

		if ($map < 0 || $map > @{$char->{warp}{memo}}) {
			error TF("Invalid map number %s.\n", $map);
		} else {
			my $name = $char->{warp}{memo}[$map];
			my $rsw = "$name.rsw";
			message TF("Attempting to open a warp portal to %s (%s)\n", 
				$maps_lut{$rsw}, $name), "info";
			sendOpenWarp($net, "$name.gat");
		}

	} elsif ($map eq 'list') {
		if (!$char->{warp}{memo} || !@{$char->{warp}{memo}}) {
			error T("You didn't cast warp portal.\n");
			return;
		}

		message T("----------------- Warp Portal --------------------\n" .
			"#  Place                           Map\n", "list");
		for (my $i = 0; $i < @{$char->{warp}{memo}}; $i++) {
			message(swrite(
				"@< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<",
				[$i, $maps_lut{$char->{warp}{memo}[$i].'.rsw'},
				$char->{warp}{memo}[$i]]),
				"list");
		}
		message("--------------------------------------------------\n", "list");

	} elsif (!defined $maps_lut{$map.'.rsw'}) {
		error TF("Map '%s' does not exist.\n", $map);

	} else {
		my $rsw = "$map.rsw";
		message TF("Attempting to open a warp portal to %s (%s)\n", 
			$maps_lut{$rsw}, $map), "info";
		sendOpenWarp($net, "$map.gat");
	}
}

sub cmdWeight {
	my (undef, $itemWeight) = @_;

	$itemWeight ||= 1;

	if ($itemWeight !~ /^\d+(\.\d+)?$/) {
		error T("Syntax error in function 'weight' (Inventory Weight Info)\n" .
			"Usage: weight [item weight]\n");
		return;
	}

	my $itemString = $itemWeight == 1 ? '' : "*$itemWeight";
	message TF("Weight: %s/%s (%s\%)\n", $char->{weight}, $char->{weight_max}, sprintf("%.02f", $char->weight_percent)), "list";
	if ($char->weight_percent < 90) {
		if ($char->weight_percent < 50) {
			my $weight_50 = int((int($char->{weight_max}*0.5) - $char->{weight}) / $itemWeight);
			message TF("You can carry %s%s before %s overweight.\n", 
				$weight_50, $itemString, '50%'), "list";
		} else {
			message TF("You are %s overweight.\n", '50%'), "list";
		}
		my $weight_90 = int((int($char->{weight_max}*0.9) - $char->{weight}) / $itemWeight);
		message TF("You can carry %s%s before %s overweight.\n", 
			$weight_90, $itemString, '90%'), "list";
	} else {
		message TF("You are %s overweight.\n", '90%');
	}
}

sub cmdWhere {
	my $pos = calcPosition($char);
	message TF("Location %s (%s) : %d, %d\n", $maps_lut{$field{name}.'.rsw'}, 
		$field{name}, $pos->{x}, $pos->{y}), "info";
}

sub cmdWho {
	sendWho($net);
}

sub cmdWhoAmI {
	my $GID = unpack("L1", $charID);
	my $AID = unpack("L1", $accountID);
	message TF("Name:    %s (Level %s %s %s)\n" .
		"Char ID: %s\n" .
		"Acct ID: %s\n", 
		$char->{name}, $char->{lv}, $sex_lut{$char->{sex}}, $jobs_lut{$char->{jobID}}, 
		$GID, $AID), "list";
}

return 1;
