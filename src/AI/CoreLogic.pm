#########################################################################
#  OpenKore - AI
#  Copyright (c) OpenKore Team
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#
#  $Revision: 4286 $
#  $Id: Commands.pm 4286 2006-04-17 14:02:27Z illusion_kore $
#
#########################################################################
#
# This module contains the core AI logic.

package AI::CoreLogic;

use strict;
use Time::HiRes qw(time);
use Carp::Assert;
use IO::Socket;
use Text::ParseWords;
use Carp::Assert;
use encoding 'utf8';

use Globals;
use Log qw(message warning error debug);
use Network::Send;
use Settings;
use AI;
use ChatQueue;
use Utils;
use Misc;
use Commands;
use FileParsers;
use Translation;


sub iterate {
	Benchmark::begin("ai_prepare") if DEBUG;

	if (timeOut($timeout{ai_wipe_check})) {
		my $timeout = $timeout{ai_wipe_old}{timeout};

		foreach (keys %players_old) {
			if (timeOut($players_old{$_}{'gone_time'}, $timeout)) {
				delete $players_old{$_};
				binRemove(\@playersID_old, $_);
			}
		}
		foreach (keys %monsters_old) {
			if (timeOut($monsters_old{$_}{'gone_time'}, $timeout)) {
				delete $monsters_old{$_};
				binRemove(\@monstersID_old, $_);
			}
		}
		foreach (keys %npcs_old) {
			delete $npcs_old{$_} if (time - $npcs_old{$_}{'gone_time'} >= $timeout{'ai_wipe_old'}{'timeout'});
		}
		foreach (keys %items_old) {
			delete $items_old{$_} if (time - $items_old{$_}{'gone_time'} >= $timeout{'ai_wipe_old'}{'timeout'});
		}
		foreach (keys %portals_old) {
			if (timeOut($portals_old{$_}{gone_time}, $timeout)) {
				delete $portals_old{$_};
				binRemove(\@portalsID_old, $_);
			}
		}

		# Remove players that are too far away; sometimes they don't get
		# removed from the list for some reason
		#foreach (keys %players) {
		#	if (distance($char->{pos_to}, $players{$_}{pos_to}) > 35) {
		#		$playersList->remove($players{$_});
		#		last;
		#	}
		#}

		$timeout{'ai_wipe_check'}{'time'} = time;
		debug "Wiped old\n", "ai", 2;
	}

	if (timeOut($timeout{ai_getInfo})) {
		processNameRequestQueue(\@unknownPlayers, \%players);
		processNameRequestQueue(\@unknownNPCs, \%npcs);

		foreach (keys %monsters) {
			if ($monsters{$_}{'name'} =~ /Unknown/) {
				sendGetPlayerInfo($net, $_);
				last;
			}
		}
		foreach (keys %pets) {
			if ($pets{$_}{'name_given'} =~ /Unknown/) {
				sendGetPlayerInfo($net, $_);
				last;
			}
		}
		$timeout{ai_getInfo}{time} = time;
	}

	if (timeOut($timeout{ai_sync})) {
		$timeout{ai_sync}{time} = time;
		sendSync($net);
	}

	if (timeOut($char->{muted}, $char->{mute_period})) {
		delete $char->{muted};
		delete $char->{mute_period};
	}

	Benchmark::end("ai_prepare") if DEBUG;


	processPortalRecording();

	return if (!$AI);



	##### MANUAL AI STARTS HERE #####

	Plugins::callHook('AI_pre/manual');

	if (AI::action eq "look" && timeOut($timeout{'ai_look'})) {
		$timeout{'ai_look'}{'time'} = time;
		sendLook($net, AI::args->{'look_body'}, AI::args->{'look_head'});
		AI::dequeue;
	}


	##### CLIENT SUSPEND #####
	# The clientSuspend AI sequence is used to freeze all other AI activity
	# for a certain period of time.

	if (AI::action eq 'clientSuspend' && timeOut(AI::args)) {
		debug "AI suspend by clientSuspend dequeued\n";
		AI::dequeue;
	} elsif (AI::action eq "clientSuspend" && $net->clientAlive()) {
		# When XKore mode is turned on, clientSuspend will increase it's timeout
		# every time the user tries to do something manually.
		my $args = AI::args;

		if ($args->{'type'} eq "0089") {
			# Player's manually attacking
			if ($args->{'args'}[0] == 2) {
				if ($chars[$config{'char'}]{'sitting'}) {
					$args->{'time'} = time;
				}
			} elsif ($args->{'args'}[0] == 3) {
				$args->{'timeout'} = 6;
			} else {
				my $ID = $args->{args}[1];
				my $monster = $monstersList->getByID($ID);

				if (!$args->{'forceGiveup'}{'timeout'}) {
					$args->{'forceGiveup'}{'timeout'} = 6;
					$args->{'forceGiveup'}{'time'} = time;
				}
				if ($monster) {
					$args->{time} = time;
					$args->{dmgFromYou_last} = $monster->{dmgFromYou};
					$args->{missedFromYou_last} = $monster->{missedFromYou};
					if ($args->{dmgFromYou_last} != $monster->{dmgFromYou}) {
						$args->{forceGiveup}{time} = time;
					}
				} else {
					$args->{time} -= $args->{'timeout'};
				}
				if (timeOut($args->{forceGiveup})) {
					$args->{time} -= $args->{timeout};
				}
			}

		} elsif ($args->{'type'} eq "009F") {
			# Player's manually picking up an item
			if (!$args->{'forceGiveup'}{'timeout'}) {
				$args->{'forceGiveup'}{'timeout'} = 4;
				$args->{'forceGiveup'}{'time'} = time;
			}
			if ($items{$args->{'args'}[0]}) {
				$args->{'time'} = time;
			} else {
				$args->{'time'} -= $args->{'timeout'};
			}
			if (timeOut($args->{'forceGiveup'})) {
				$args->{'time'} -= $args->{'timeout'};
			}
		}

		# Client suspended, do not continue with AI
		return;
	}


	processNPCTalk();

	##### DROPPING #####
	# Drop one or more items from inventory.

	if (AI::action eq "drop" && timeOut(AI::args)) {
		my $item = AI::args->{'items'}[0];
		my $amount = AI::args->{max};

		drop($item, $amount);
		shift @{AI::args->{items}};
		AI::args->{time} = time;
		AI::dequeue if (@{AI::args->{'items'}} <= 0);
	}

	##### ESCAPE UNKNOWN MAPS #####      
	# escape from unknown maps. Happens when kore accidentally teleports onto an
	# portal. With this, kore should automaticly go into the portal on the other side
	# Todo: Make kore do a random walk searching for portal if there's no portal arround.

	if (AI::action eq "escape" && $AI == 2) {
		my $skip = 0;
		if (timeOut($timeout{ai_route_escape}) && $timeout{ai_route_escape}{time}){
			AI::dequeue;
			if ($portalsID[0]) {
				message T("Escaping to into nearest portal.\n");
				main::ai_route($field{name}, $portals{$portalsID[0]}{'pos'}{'x'},
					$portals{$portalsID[0]}{'pos'}{'y'}, attackOnRoute => 1, noSitAuto => 1);
				$skip = 1;

			} elsif ($spellsID[0]){   #get into the first portal you see
			     my $spell = $spells{$spellsID[0]};
				if (getSpellName($spell->{type}) eq "Warp Portal" ){
					message T("Found warp portal escaping into warp portal.\n");
					main::ai_route($field{name}, $spell->{pos}{x},
						$spell->{pos}{y}, attackOnRoute => 1, noSitAuto => 1);
					$skip = 1;
				}else{
					error T("Escape failed no portal found.\n");;
				}
				
			} else {
				error T("Escape failed no portal found.\n");
			}
	     }
		if ($config{route_escape_randomWalk} && !$skip) { #randomly search for portals...
		   my ($randX, $randY);
		   my $i = 500;
		   my $pos = calcPosition($char);
		   do {
			   	 if ((rand(2)+1)%2){
				    $randX = $pos->{x} + int(rand(9) + 1);
	   		  	 }else{
	 	  	 	    $randX = $pos->{x} - int(rand(9) + 1);
	    	           }
				 if ((rand(2)+1)%2){
					$randY = $pos->{y} + int(rand(9) + 1);
	                }else{
		               $randY = $pos->{y} - int(rand(9) + 1);
		     	 }
		   } while (--$i && !checkFieldWalkable(\%field, $randX, $randY));
			   	if (!$i) {
				   error T("Invalid coordinates specified for randomWalk (coordinates are unwalkable); randomWalk disabled\n");
	 	   		} else {
			        message TF("Calculating random route to: %s(%s): %s, %s\n", $maps_lut{$field{name}.'.rsw'}, $field{name}, $randX, $randY), "route";
				   ai_route($field{name}, $randX, $randY,
				   maxRouteTime => $config{route_randomWalk_maxRouteTime},
				   			 attackOnRoute => 2,
					  		 noMapRoute => ($config{route_randomWalk} == 2 ? 1 : 0) );
			     }
		    }
	}

	##### DELAYED-TELEPORT #####

	if (AI::action eq 'teleport') {
		if ($timeout{ai_teleport_delay}{time} && timeOut($timeout{ai_teleport_delay})) {
			# We have already successfully used the Teleport skill,
			# and the ai_teleport_delay timeout has elapsed
			sendTeleport($net, AI::args->{lv} == 2 ? "$config{saveMap}.gat" : "Random");
			AI::dequeue;
		} elsif (!$timeout{ai_teleport_delay}{time} && timeOut($timeout{ai_teleport_retry})) {
			# We are still trying to use the Teleport skill
			sendSkillUse($net, 26, $char->{skills}{AL_TELEPORT}{lv}, $accountID);
			$timeout{ai_teleport_retry}{time} = time;
		}
	}

	processSit();
	processStand();
	processAttack();
	processSkillUse();
	processRouteAI();
	processMapRouteAI();


	##### TAKE #####

	if (AI::action eq "take" && AI::args->{suspended}) {
		AI::args->{ai_take_giveup}{time} += time - AI::args->{suspended};
		delete AI::args->{suspended};
	}

	if (AI::action eq "take" && ( !$items{AI::args->{ID}} || !%{$items{AI::args->{ID}}} )) {
		AI::dequeue;

	} elsif (AI::action eq "take" && timeOut(AI::args->{ai_take_giveup})) {
		my $item = $items{AI::args->{ID}};
		message TF("Failed to take %s (%s) from (%s, %s) to (%s, %s)\n", $item->{name}, $item->{binID}, $char->{pos}{x}, $char->{pos}{y}, $item->{pos}{x}, $item->{pos}{y});
		$items{AI::args->{ID}}{take_failed}++;
		AI::dequeue;

	} elsif (AI::action eq "take") {
		my $ID = AI::args->{ID};
		my $myPos = $char->{pos_to};
		my $dist = distance($items{$ID}{pos}, $myPos);
		my $item = $items{AI::args->{ID}};
		debug "Planning to take $item->{name} ($item->{binID}), distance $dist\n", "drop";

		if ($char->{sitting}) {
			stand();

		} elsif ($dist > 2) {
			if (!$config{itemsTakeAuto_new}) {
				my (%vec, %pos);
				getVector(\%vec, $item->{pos}, $myPos);
				moveAlongVector(\%pos, $myPos, \%vec, $dist - 1);
				move($pos{x}, $pos{y});
			} else {
				my $pos = $item->{pos};
				message TF("Routing to (%s, %s) to take %s (%s), distance %s\n", $pos->{x}, $pos->{y}, $item->{name}, $item->{binID}, $dist);
				ai_route($field{name}, $pos->{x}, $pos->{y}, maxRouteDistance => $config{'attackMaxRouteDistance'});
			}

		} elsif (timeOut($timeout{ai_take})) {
			my %vec;
			my $direction;
			getVector(\%vec, $item->{pos}, $myPos);
			$direction = int(sprintf("%.0f", (360 - vectorToDegree(\%vec)) / 45)) % 8;
			sendLook($net, $direction, 0) if ($direction != $char->{look}{body});
			sendTake($net, $ID);
			$timeout{ai_take}{time} = time;
		}
	}


	##### MOVE #####

	if (AI::action eq "move") {
		AI::args->{ai_move_giveup}{time} = time unless AI::args->{ai_move_giveup}{time};

		# Wait until we've stand up, if we're sitting
		if ($char->{sitting}) {
			AI::args->{ai_move_giveup}{time} = 0;
			stand();

		# Stop if the map changed
		} elsif (AI::args->{mapChanged}) {
			debug "Move - map change detected\n", "ai_move";
			AI::dequeue;

		# Stop if we've moved
		} elsif (AI::args->{time_move} != $char->{time_move}) {
			debug "Move - moving\n", "ai_move";
			AI::dequeue;

		# Stop if we've timed out
		} elsif (timeOut(AI::args->{ai_move_giveup})) {
			debug "Move - timeout\n", "ai_move";
			AI::dequeue;

		} elsif (timeOut($AI::Timeouts::move_retry, 0.5)) {
			# No update yet, send move request again.
			# We do this every 0.5 secs
			$AI::Timeouts::move_retry = time;
			sendMove(AI::args->{move_to}{x}, AI::args->{move_to}{y});
		}
	}


	return if ($AI != 2);



	##### REAL AI STARTS HERE #####

	Plugins::callHook('AI_pre');

	if (!$accountID) {
		$AI = 0;
		injectAdminMessage("Please relogin to enable X-${Settings::NAME}.") if ($config{'verbose'});
		return;
	}

	ChatQueue::processFirst;


	##### MISC #####

	if (AI::action eq "equip") {
		#just wait until everything is equipped or timedOut
		if (!$ai_v{temp}{waitForEquip} || timeOut($timeout{ai_equip_giveup})) {
			AI::dequeue;
			delete $ai_v{temp}{waitForEquip};
		}
	}

	if (AI::action ne "deal" && %currentDeal) {
		AI::queue('deal');
	} elsif (AI::action eq "deal") {
		if (%currentDeal) {
			if (!$currentDeal{you_finalize} && timeOut($timeout{ai_dealAuto}) &&
			    ($config{dealAuto} == 2 ||
				 $config{dealAuto} == 3 && $currentDeal{other_finalize})) {
				sendDealAddItem(0, $currentDeal{'you_zenny'});
				sendDealFinalize();
				$timeout{ai_dealAuto}{time} = time;
			} elsif ($currentDeal{other_finalize} && $currentDeal{you_finalize} &&timeOut($timeout{ai_dealAuto}) && $config{dealAuto} >= 2) {
				sendDealTrade($net);
				$timeout{ai_dealAuto}{time} = time;
			}
		} else {
			AI::dequeue();
		}
	}

	# dealAuto 1=refuse 2,3=accept
	if ($config{'dealAuto'} && %incomingDeal) {
		if ($config{'dealAuto'} == 1 && timeOut($timeout{ai_dealAutoCancel})) {
			sendDealCancel($net);
			$timeout{'ai_dealAuto'}{'time'} = time;
		} elsif ($config{'dealAuto'} >= 2 && timeOut($timeout{ai_dealAuto})) {
			sendDealAccept($net);
			$timeout{'ai_dealAuto'}{'time'} = time;
		}
	}


	# partyAuto 1=refuse 2=accept
	if ($config{'partyAuto'} && %incomingParty && timeOut($timeout{'ai_partyAuto'})) {
		if ($config{partyAuto} == 1) {
			message T("Auto-denying party request\n");
		} else {
			message T("Auto-accepting party request\n");
		}
		sendPartyJoin($net, $incomingParty{'ID'}, $config{'partyAuto'} - 1);
		$timeout{'ai_partyAuto'}{'time'} = time;
		undef %incomingParty;
	}

	if ($config{'guildAutoDeny'} && %incomingGuild && timeOut($timeout{'ai_guildAutoDeny'})) {
		sendGuildJoin($net, $incomingGuild{'ID'}, 0) if ($incomingGuild{'Type'} == 1);
		sendGuildAlly($net, $incomingGuild{'ID'}, 0) if ($incomingGuild{'Type'} == 2);
		$timeout{'ai_guildAutoDeny'}{'time'} = time;
		undef %incomingGuild;
	}


	if ($net->clientAlive() && !$sentWelcomeMessage && timeOut($timeout{'welcomeText'})) {
		injectAdminMessage($Settings::welcomeText) if ($config{'verbose'} && !$config{'XKore_silent'});
		$sentWelcomeMessage = 1;
	}


	##### AUTOBREAKTIME #####
	# Break time: automatically disconnect at certain times of the day
	if (timeOut($AI::Timeouts::autoBreakTime, 30)) {
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
		my $hormin = sprintf("%02d:%02d", $hour, $min);
		my @wdays = ('sun','mon','tue','wed','thu','fri','sat');
		debug "autoBreakTime: hormin = $hormin, weekday = $wdays[$wday]\n", "autoBreakTime", 2;
		for (my $i = 0; exists $config{"autoBreakTime_$i"}; $i++) {
			next if (!$config{"autoBreakTime_$i"});

			if  ( ($wdays[$wday] eq lc($config{"autoBreakTime_$i"})) || (lc($config{"autoBreakTime_$i"}) eq "all") ) {
				if ($config{"autoBreakTime_${i}_startTime"} eq $hormin) {
					my ($hr1, $min1) = split /:/, $config{"autoBreakTime_${i}_startTime"};
					my ($hr2, $min2) = split /:/, $config{"autoBreakTime_${i}_stopTime"};
					my $time1 = $hr1 * 60 * 60 + $min1 * 60;
					my $time2 = $hr2 * 60 * 60 + $min2 * 60;
					my $diff = ($time2 - $time1) % (60 * 60 * 24);

					message TF("\nDisconnecting due to break time: %s to %s\n\n", $config{"autoBreakTime_$i"."_startTime"}, $config{"autoBreakTime_$i"."_stopTime"}), "system";
					chatLog("k", TF("*** Disconnected due to Break Time: %s to %s ***\n", $config{"autoBreakTime_$i"."_startTime"}, $config{"autoBreakTime_$i"."_stopTime"}));

					$timeout_ex{'master'}{'timeout'} = $diff;
					$timeout_ex{'master'}{'time'} = time;
					$KoreStartTime = time;
					$net->serverDisconnect();
					AI::clear();
					undef %ai_v;
					$conState = 1;
					undef $conState_tries;
					last;
				}
			}
		}
		$AI::Timeouts::autoBreakTime = time;
	}


	##### WAYPOINT ####

	if (AI::action eq "waypoint") {
		my $args = AI::args;

		if (defined $args->{walkedTo}) {
			message TF("Arrived at waypoint %s\n",$args->{walkedTo}), "waypoint";
			Plugins::callHook('waypoint/arrived', {
				points => $args->{points},
				index => $args->{walkedTo}
			});
			delete $args->{walkedTo};

		} elsif ($args->{index} > -1 && $args->{index} < @{$args->{points}}) {
			# Walk to the next point
			my $point = $args->{points}[$args->{index}];
			message TF("Walking to waypoint %s: %s(%s): %s,%s\n", $args->{index}, $maps_lut{$point->{map}}, $point->{map}, $point->{x}, $point->{y}), "waypoint";
			$args->{walkedTo} = $args->{index};
			$args->{index} += $args->{inc};

			my $result = ai_route($point->{map}, $point->{x}, $point->{y},
				attackOnRoute => $args->{attackOnRoute},
				tags => "waypoint");
			if (!$result) {
				error TF("Unable to calculate how to walk to %s (%s, %s)\n", $point->{map}, $point->{x}, $point->{y});
				AI::dequeue;            
			}

		} else {
			# We're at the end of the waypoint.
			# Figure out what to do now.
			if (!$args->{whenDone}) {
				AI::dequeue;

			} elsif ($args->{whenDone} eq 'repeat') {
				$args->{index} = 0;

			} elsif ($args->{whenDone} eq 'reverse') {
				if ($args->{inc} < 0) {
					$args->{inc} = 1;
					$args->{index} = 1;
					$args->{index} = 0 if ($args->{index} > $#{$args->{points}});
				} else {
					$args->{inc} = -1;
					$args->{index} -= 2;
					$args->{index} = 0 if ($args->{index} < 0);
				}
			}
		}
	}


	##### DEAD #####

	if (AI::action eq "dead" && !$char->{dead}) {
		AI::dequeue;

		if ($char->{resurrected}) {
			# We've been resurrected
			$char->{resurrected} = 0;

		} else {
			# Force storage after death
			if ($config{storageAuto} && !$config{storageAuto_notAfterDeath}) {
				message T("Auto-storaging due to death\n");
				AI::queue("storageAuto");
			}

			if ($config{autoMoveOnDeath} && $config{autoMoveOnDeath_x} && $config{autoMoveOnDeath_y} && $config{autoMoveOnDeath_map}) {
				message TF("Moving to %s - %d,%d\n", $config{autoMoveOnDeath_map}, $config{autoMoveOnDeath_x}, $config{autoMoveOnDeath_y});
				AI::queue("sitAuto");
				ai_route($config{autoMoveOnDeath_map}, $config{autoMoveOnDeath_x}, $config{autoMoveOnDeath_y});
				}

		}

	} elsif (AI::action ne "dead" && AI::action ne "deal" && $char->{'dead'}) {
		AI::clear();
		AI::queue("dead");
	}

	if (AI::action eq "dead" && $config{dcOnDeath} != -1 && time - $char->{dead_time} >= $timeout{ai_dead_respawn}{timeout}) {
		sendRespawn($net);
		$char->{'dead_time'} = time;
	}

	if (AI::action eq "dead" && $config{dcOnDeath} && $config{dcOnDeath} != -1) {
		message T("Disconnecting on death!\n");
		chatLog("k", T("*** You died, auto disconnect! ***\n"));
		$quit = 1;
	}

	##### STORAGE GET #####
	# Get one or more items from storage.

	if (AI::action eq "storageGet" && timeOut(AI::args)) {
		my $item = shift @{AI::args->{items}};
		my $amount = AI::args->{max};

		if (!$amount || $amount > $item->{amount}) {
			$amount = $item->{amount};
		}
		sendStorageGet($item->{index}, $amount) if $storage{opened};
		AI::args->{time} = time;
		AI::dequeue if !@{AI::args->{items}};
	}

	#### CART ADD ####
	# Put one or more items in cart.
	# TODO: check for cart weight & number of items

	if (AI::action eq "cartAdd" && timeOut(AI::args)) {
		my $item = AI::args->{items}[0];
		my $i = $item->{index};

		if ($char->{inventory}[$i]) {
			my $amount = $item->{amount};
			if (!$amount || $amount > $char->{inventory}[$i]{amount}) {
				$amount = $char->{inventory}[$i]{amount};
			}
			sendCartAdd($char->{inventory}[$i]{index}, $amount);
		}
		shift @{AI::args->{items}};
		AI::args->{time} = time;
		AI::dequeue if (@{AI::args->{items}} <= 0);
	}

	#### CART Get ####
	# Get one or more items from cart.

	if (AI::action eq "cartGet" && timeOut(AI::args)) {
		my $item = AI::args->{items}[0];
		my $i = $item->{index};

		if ($cart{inventory}[$i]) {
			my $amount = $item->{amount};
			if (!$amount || $amount > $cart{inventory}[$i]{amount}) {
				$amount = $cart{inventory}[$i]{amount};
			}
			sendCartGet($i, $amount);
		}
		shift @{AI::args->{items}};
		AI::args->{time} = time;
		AI::dequeue if (@{AI::args->{items}} <= 0);
	}


	####### AUTO MAKE ARROW #######
	if ((AI::isIdle || AI::is(qw/route move autoBuy storageAuto follow sitAuto items_take items_gather/))
	 && timeOut($AI::Timeouts::autoArrow, 0.2) && $config{autoMakeArrows} && defined binFind(\@skillsID, 'AC_MAKINGARROW') ) {
		my $max = @arrowCraftID;
		for (my $i = 0; $i < $max; $i++) {
			my $item = $char->{inventory}[$arrowCraftID[$i]];
			next if (!$item);
			if ($arrowcraft_items{lc($item->{name})}) {
				sendArrowCraft($net, $item->{nameID});
				debug "Making item\n", "ai_makeItem";
				last;
			}
		}
		$AI::Timeouts::autoArrow = time;
	}

	if ($config{autoMakeArrows} && $useArrowCraft) {
		if (defined binFind(\@skillsID, 'AC_MAKINGARROW')) {
			ai_skillUse('AC_MAKINGARROW', 1, 0, 0, $accountID);
		}
		undef $useArrowCraft;
	}


	processAutoStorage();



	#####AUTO SELL#####

	AUTOSELL: {

		if ((AI::action eq "" || AI::action eq "route" || AI::action eq "sitAuto" || AI::action eq "follow")
			&& (($config{'itemsMaxWeight_sellOrStore'} && percent_weight($char) >= $config{'itemsMaxWeight_sellOrStore'})
				|| ($config{'itemsMaxNum_sellOrStore'} && @{$char->{inventory}} >= $config{'itemsMaxNum_sellOrStore'})
				|| (!$config{'itemsMaxWeight_sellOrStore'} && percent_weight($char) >= $config{'itemsMaxWeight'})
				)
			&& $config{'sellAuto'}
			&& $config{'sellAuto_npc'} ne ""
			&& !$ai_v{sitAuto_forcedBySitCommand}
		  ) {
			$ai_v{'temp'}{'ai_route_index'} = AI::findAction("route");
			if ($ai_v{'temp'}{'ai_route_index'} ne "") {
				$ai_v{'temp'}{'ai_route_attackOnRoute'} = AI::args($ai_v{'temp'}{'ai_route_index'})->{'attackOnRoute'};
			}
			if (!($ai_v{'temp'}{'ai_route_index'} ne "" && $ai_v{'temp'}{'ai_route_attackOnRoute'} <= 1) && ai_sellAutoCheck()) {
				AI::queue("sellAuto");
			}
		}

		if (AI::action eq "sellAuto" && AI::args->{'done'}) {
			my $var = AI::args->{'forcedByBuy'};
			my $var2 = AI::args->{'forcedByStorage'};
			message T("Auto-sell sequence completed.\n"), "success";
			AI::dequeue;
			if ($var2) {
				AI::queue("buyAuto", {forcedByStorage => 1});
			} elsif (!$var) {
				AI::queue("buyAuto", {forcedBySell => 1});
			}
		} elsif (AI::action eq "sellAuto" && timeOut($timeout{'ai_sellAuto'})) {
			my $args = AI::args;

			$args->{'npc'} = {};
			my $destination = $config{sellAuto_standpoint} || $config{sellAuto_npc};
			getNPCInfo($destination, $args->{'npc'});
			if (!defined($args->{'npc'}{'ok'})) {
				$args->{'done'} = 1;
				last AUTOSELL;
			}

			undef $ai_v{'temp'}{'do_route'};
			if ($field{'name'} ne $args->{'npc'}{'map'}) {
				$ai_v{'temp'}{'do_route'} = 1;
			} else {
				$ai_v{'temp'}{'distance'} = distance($args->{'npc'}{'pos'}, $chars[$config{'char'}]{'pos_to'});
				$config{'sellAuto_distance'} = 1 if ($config{sellAuto_standpoint});
				if ($ai_v{'temp'}{'distance'} > $config{'sellAuto_distance'}) {
					$ai_v{'temp'}{'do_route'} = 1;
				}
			}
			if ($ai_v{'temp'}{'do_route'}) {
				if ($args->{'warpedToSave'} && !$args->{'mapChanged'}) {
					undef $args->{'warpedToSave'};
				}

				if ($config{'saveMap'} ne "" && $config{'saveMap_warpToBuyOrSell'} && !$args->{'warpedToSave'}
				&& !$cities_lut{$field{'name'}.'.rsw'} && $config{'saveMap'} ne $field{name}) {
					$args->{'warpedToSave'} = 1;
					message T("Teleporting to auto-sell\n"), "teleport";
					useTeleport(2);
					$timeout{'ai_sellAuto'}{'time'} = time;
				} else {
	 				message TF("Calculating auto-sell route to: %s(%s): %s, %s\n", $maps_lut{$ai_seq_args[0]{'npc'}{'map'}.'.rsw'}, $ai_seq_args[0]{'npc'}{'map'}, $ai_seq_args[0]{'npc'}{'pos'}{'x'}, $ai_seq_args[0]{'npc'}{'pos'}{'y'}), "route";
					ai_route($args->{'npc'}{'map'}, $args->{'npc'}{'pos'}{'x'}, $args->{'npc'}{'pos'}{'y'},
						attackOnRoute => 1,
						distFromGoal => $config{'sellAuto_distance'},
						noSitAuto => 1);
				}
			} else {
				$args->{'npc'} = {};
				getNPCInfo($config{'sellAuto_npc'}, $args->{'npc'});
				if (!defined($args->{'sentSell'})) {
					$args->{'sentSell'} = 1;

					# load the real npc location just in case we used standpoint
					my $realpos = {};
					getNPCInfo($config{"sellAuto_npc"}, $realpos);

					ai_talkNPC($realpos->{pos}{x}, $realpos->{pos}{y}, 's e');

					last AUTOSELL;
				}
				$args->{'done'} = 1;

				# Form list of items to sell
				my @sellItems;
				for (my $i = 0; $i < @{$char->{inventory}};$i++) {
					my $item = $char->{inventory}[$i];
					next if (!$item || !%{$item} || $item->{equipped});

					my $control = items_control($item->{name});

					if ($control->{'sell'} && $item->{'amount'} > $control->{keep}) {
						if ($args->{lastIndex} ne "" && $args->{lastIndex} == $item->{index} && timeOut($timeout{'ai_sellAuto_giveup'})) {
							last AUTOSELL;
						} elsif ($args->{lastIndex} eq "" || $args->{lastIndex} != $item->{index}) {
							$timeout{ai_sellAuto_giveup}{time} = time;
						}
						undef $args->{done};
						$args->{lastIndex} = $item->{index};

						my %obj;
						$obj{index} = $item->{index};
						$obj{amount} = $item->{amount} - $control->{keep};
						push @sellItems, \%obj;

						$timeout{ai_sellAuto}{time} = time;
					}
				}
				sendSellBulk($net, \@sellItems) if (@sellItems);

				if ($args->{done}) {
					# plugins can hook here and decide to keep sell going longer
					my %hookArgs;
					Plugins::callHook("AI_sell_done", \%hookArgs);
					undef $args->{done} if ($hookArgs{return});
				}

			}
		}

	} #END OF BLOCK AUTOSELL



	#####AUTO BUY#####

	AUTOBUY: {

		if ((AI::action eq "" || AI::action eq "route" || AI::action eq "follow") && timeOut($timeout{'ai_buyAuto'}) && time > $ai_v{'inventory_time'}) {
			undef $ai_v{'temp'}{'found'};
			my $i = 0;
			while (1) {
				last if (!$config{"buyAuto_$i"} || !$config{"buyAuto_$i"."_npc"});
				$ai_v{'temp'}{'invIndex'} = findIndexString_lc(\@{$chars[$config{'char'}]{'inventory'}}, "name", $config{"buyAuto_$i"});
				if ($config{"buyAuto_$i"."_minAmount"} ne "" && $config{"buyAuto_$i"."_maxAmount"} ne ""
					&& (checkSelfCondition("buyAuto_$i"))
					&& ($ai_v{'temp'}{'invIndex'} eq ""
					|| ($chars[$config{'char'}]{'inventory'}[$ai_v{'temp'}{'invIndex'}]{'amount'} <= $config{"buyAuto_$i"."_minAmount"}
					&& $chars[$config{'char'}]{'inventory'}[$ai_v{'temp'}{'invIndex'}]{'amount'} < $config{"buyAuto_$i"."_maxAmount"}))) {
					$ai_v{'temp'}{'found'} = 1;
				}
				$i++;
			}
			$ai_v{'temp'}{'ai_route_index'} = AI::findAction("route");
			if ($ai_v{'temp'}{'ai_route_index'} ne "") {
				$ai_v{'temp'}{'ai_route_attackOnRoute'} = AI::args($ai_v{'temp'}{'ai_route_index'})->{'attackOnRoute'};
			}
			if (!($ai_v{'temp'}{'ai_route_index'} ne "" && $ai_v{'temp'}{'ai_route_attackOnRoute'} <= 1) && $ai_v{'temp'}{'found'}) {
				AI::queue("buyAuto");
			}
			$timeout{'ai_buyAuto'}{'time'} = time;
		}

		if (AI::action eq "buyAuto" && AI::args->{'done'}) {
			# buyAuto finished
			$ai_v{'temp'}{'var'} = AI::args->{'forcedBySell'};
			$ai_v{'temp'}{'var2'} = AI::args->{'forcedByStorage'};
			AI::dequeue;

			if ($ai_v{'temp'}{'var'} && $config{storageAuto}) {
				AI::queue("storageAuto", {forcedBySell => 1});
			} elsif (!$ai_v{'temp'}{'var2'} && $config{storageAuto}) {
				AI::queue("storageAuto", {forcedByBuy => 1});
			}

		} elsif (AI::action eq "buyAuto" && timeOut($timeout{ai_buyAuto_wait}) && timeOut($timeout{ai_buyAuto_wait_buy})) {
			my $args = AI::args;
			undef $args->{index};

			for (my $i = 0; exists $config{"buyAuto_$i"}; $i++) {
				next if (!$config{"buyAuto_$i"});
				# did we already fail to do this buyAuto slot? (only fails in this way if the item is nonexistant)
				next if ($args->{index_failed}{$i});

				$args->{invIndex} = findIndexString_lc($char->{inventory}, "name", $config{"buyAuto_$i"});
				if ($config{"buyAuto_$i"."_maxAmount"} ne "" && ($args->{invIndex} eq "" || $char->{inventory}[$args->{invIndex}]{amount} < $config{"buyAuto_$i"."_maxAmount"})) {
					next if ($config{"buyAuto_$i"."_zeny"} && !inRange($char->{zenny}, $config{"buyAuto_$i"."_zeny"}));

					# get NPC info, use standpoint if provided
					$args->{npc} = {};
					my $destination = $config{"buyAuto_$i"."_standpoint"} || $config{"buyAuto_$i"."_npc"};
					getNPCInfo($destination, $args->{npc});

					# did we succeed to load NPC info from this slot?
					# (doesnt check validity of _npc if we used _standpoint...)
					if ($args->{npc}{ok}) {
						$args->{index} = $i;
					}
					last;
				}



			}

			# failed to load any slots for buyAuto (we're done or they're all invalid)
			# what does the second check do here?
			if ($args->{index} eq "" || ($args->{lastIndex} ne "" && $args->{lastIndex} == $args->{index} && timeOut($timeout{'ai_buyAuto_giveup'}))) {
				$args->{'done'} = 1;
				last AUTOBUY;
			}

			my $do_route;

			if ($field{name} ne $args->{npc}{map}) {
				# we definitely need to route if we're on the wrong map
				$do_route = 1;
			} else {
				my $distance = distance($args->{npc}{pos}, $char->{pos_to});
				# move exactly to the given spot if we specified a standpoint
				my $talk_distance = ($config{"buyAuto_$args->{index}"."_standpoint"} ? 1 : $config{"buyAuto_$args->{index}"."_distance"});
				if ($distance > $talk_distance) {
					$do_route = 1;
				}
			}
			if ($do_route) {
				if ($args->{warpedToSave} && !$args->{mapChanged}) {
					undef $args->{warpedToSave};
				}

				if ($config{'saveMap'} ne "" && $config{'saveMap_warpToBuyOrSell'} && !$args->{warpedToSave}
				&& !$cities_lut{$field{'name'}.'.rsw'} && $config{'saveMap'} ne $field{name}) {
					$args->{warpedToSave} = 1;
					message T("Teleporting to auto-buy\n"), "teleport";
					useTeleport(2);
					$timeout{ai_buyAuto_wait}{time} = time;
				} else {
	 				message TF("Calculating auto-buy route to: %s (%s): %s, %s\n", $maps_lut{$args->{npc}{map}.'.rsw'}, $args->{npc}{map}, $args->{npc}{pos}{x}, $args->{npc}{pos}{y}), "route";
					ai_route($args->{npc}{map}, $args->{npc}{pos}{x}, $args->{npc}{pos}{y},
						attackOnRoute => 1,
						distFromGoal => $config{"buyAuto_$args->{index}"."_distance"});
				}
			} else {
				if ($args->{lastIndex} eq "" || $args->{lastIndex} != $args->{index}) {
					# if this is a different item than last loop, get new info for itemID and resend buy
					undef $args->{itemID};
					if ($config{"buyAuto_$args->{index}"."_npc"} != $config{"buyAuto_$args->{lastIndex}"."_npc"}) {
						undef $args->{sentBuy};
					}
					$timeout{ai_buyAuto_giveup}{time} = time;
				}
				$args->{lastIndex} = $args->{index};

				# find the item ID if we don't know it yet
				if ($args->{itemID} eq "") {
					if ($args->{invIndex} && $char->{inventory}[$args->{invIndex}]) {
						# if we have the item in our inventory, we can quickly get the nameID
						$args->{itemID} = $char->{inventory}[$args->{invIndex}]{nameID};
					} else {
						# scan the entire items.txt file (this is slow)
						foreach (keys %items_lut) {
							if (lc($items_lut{$_}) eq lc($config{"buyAuto_$args->{index}"})) {
								$args->{itemID} = $_;
							}
						}
					}
					if ($args->{itemID} eq "") {
						# the specified item doesn't even exist
						# don't try this index again
						$args->{index_failed}{$args->{index}} = 1;
						debug "buyAuto index $args->{index} failed, item doesn't exist\n", "npc";
						last AUTOBUY;
					}
				}

				if (!$args->{sentBuy}) {
					$args->{sentBuy} = 1;
					$timeout{ai_buyAuto_wait}{time} = time;

					# load the real npc location just in case we used standpoint
					my $realpos = {};
					getNPCInfo($config{"buyAuto_$args->{index}"."_npc"}, $realpos);

					ai_talkNPC($realpos->{pos}{x}, $realpos->{pos}{y}, 'b e');
					last AUTOBUY;
				}
				if ($args->{invIndex} ne "") {
					# this item is in the inventory already, get what we need
					sendBuy($net, $args->{'itemID'}, $config{"buyAuto_$args->{index}"."_maxAmount"} - $char->{inventory}[$args->{invIndex}]{amount});
				} else {
					# get the full amount
					sendBuy($net, $args->{itemID}, $config{"buyAuto_$args->{index}"."_maxAmount"});
				}
				$timeout{ai_buyAuto_wait_buy}{time} = time;
			}
		}

	} #END OF BLOCK AUTOBUY


	##### AUTO-CART ADD/GET ####

	if ((AI::isIdle || AI::is(qw/route move buyAuto follow sitAuto items_take items_gather/))) {
		my $timeout = $timeout{ai_cartAutoCheck}{timeout} || 2;
		if (timeOut($AI::Timeouts::autoCart, $timeout) && $cart{exists}) {
			my @addItems;
			my @getItems;
			my $inventory = $char->{inventory};
			my $cartInventory = $cart{inventory};
			my $max;

			if ($config{cartMaxWeight} && $cart{weight} < $config{cartMaxWeight}) {
				$max = @{$inventory};
				for (my $i = 0; $i < $max; $i++) {
					my $item = $inventory->[$i];
					next unless ($item);
					next if ($item->{broken} && $item->{type} == 7); # dont auto-cart add pet eggs in use
					next if ($item->{equipped});

					my $control = items_control($item->{name});

					if ($control->{cart_add} && $item->{amount} > $control->{keep}) {
						my %obj;
						$obj{index} = $i;
						$obj{amount} = $item->{amount} - $control->{keep};
						push @addItems, \%obj;
						debug "Scheduling $item->{name} ($i) x $obj{amount} for adding to cart\n", "ai_autoCart";
					}
				}
				cartAdd(\@addItems);
			}

			$max = @{$cartInventory};
			for (my $i = 0; $i < $max; $i++) {
				my $cartItem = $cartInventory->[$i];
				next unless ($cartItem);
				my $control = items_control($cartItem->{name});
				next unless ($control->{cart_get});

				my $invIndex = findIndexString_lc($inventory, "name", $cartItem->{name});
				my $amount;
				if ($invIndex eq '') {
					$amount = $control->{keep};
				} elsif ($inventory->[$invIndex]{'amount'} < $control->{keep}) {
					$amount = $control->{keep} - $inventory->[$invIndex]{'amount'};
				}
				if ($amount > $cartItem->{amount}) {
					$amount = $cartItem->{amount};
				}
				if ($amount > 0) {
					my %obj;
					$obj{index} = $i;
					$obj{amount} = $amount;
					push @getItems, \%obj;
					debug "Scheduling $cartItem->{name} ($i) x $obj{amount} for getting from cart\n", "ai_autoCart";
				}
			}
			cartGet(\@getItems);
		}
		$AI::Timeouts::autoCart = time;
	}


	##### LOCKMAP #####

	if (AI::isIdle && $config{lockMap}
		&& !$ai_v{sitAuto_forcedBySitCommand}
		&& ($field{name} ne $config{lockMap}
			|| ($config{lockMap_x} ne '' && ($char->{pos_to}{x} < $config{lockMap_x} - $config{lockMap_randX} || $char->{pos_to}{x} > $config{lockMap_x} + $config{lockMap_randX}))
			|| ($config{lockMap_y} ne '' && ($char->{pos_to}{y} < $config{lockMap_y} - $config{lockMap_randY} || $char->{pos_to}{y} > $config{lockMap_y} + $config{lockMap_randY}))
	)) {

		if ($maps_lut{$config{lockMap}.'.rsw'} eq '') {
			error TF("Invalid map specified for lockMap - map %s doesn't exist\n", $config{lockMap});
			$config{lockMap} = '';
		} else {
			my %args;
			Plugins::callHook("AI/lockMap", \%args);
			if (!$args{return}) {
				my %lockField;
				getField($config{lockMap}, \%lockField);

				my ($lockX, $lockY);
				my $i = 500;
				if ($config{lockMap_x} ne '' || $config{lockMap_y} ne '') {
					do {
						$lockX = int($config{lockMap_x}) if ($config{lockMap_x} ne '');
						$lockX = int(rand($field{width}) + 1) if (!$config{lockMap_x} && $config{lockMap_y});
						$lockX += (int(rand($config{lockMap_randX}))+1) if ($config{lockMap_randX} ne '');
						$lockY = int($config{lockMap_y}) if ($config{lockMap_y} ne '');
						$lockY = int(rand($field{width}) + 1) if (!$config{lockMap_y} && $config{lockMap_x});
						$lockY += (int(rand($config{lockMap_randY}))+1) if ($config{lockMap_randY} ne '');
					} while (--$i && !checkFieldWalkable(\%lockField, $lockX, $lockY));
				}
				if (!$i) {
					error T("Invalid coordinates specified for lockMap, coordinates are unwalkable\n");
					$config{lockMap} = '';
				} else {
					my $attackOnRoute = 2;
					$attackOnRoute = 1 if ($config{attackAuto_inLockOnly} == 1);
					$attackOnRoute = 0 if ($config{attackAuto_inLockOnly} > 1);
					if (defined $lockX || defined $lockY) {
						message TF("Calculating lockMap route to: %s(%s): %s, %s\n", $maps_lut{$config{lockMap}.'.rsw'}, $config{lockMap}, $lockX, $lockY), "route";
					} else {
						message TF("Calculating lockMap route to: %s(%s)\n", $maps_lut{$config{lockMap}.'.rsw'}, $config{lockMap}), "route";
					}
					ai_route($config{lockMap}, $lockX, $lockY, attackOnRoute => $attackOnRoute);
				}
			}
		}
	}


	##### AUTO STATS #####

	if (!$statChanged && $config{statsAddAuto}) {
		# Split list of stats/values
		my @list = split(/ *,+ */, $config{"statsAddAuto_list"});
		my $statAmount;
		my ($num, $st);

		foreach my $item (@list) {
			# Split each stat/value pair
			($num, $st) = $item =~ /(\d+) (str|vit|dex|int|luk|agi)/i;
			$st = lc $st;
			# If stat needs to be raised to match desired amount
			$statAmount = $char->{$st};
			$statAmount += $char->{"${st}_bonus"} if (!$config{statsAddAuto_dontUseBonus});

			if ($statAmount < $num && ($char->{$st} < 99 || $config{statsAdd_over_99})) {
				# If char has enough stat points free to raise stat
				if ($char->{points_free} &&
				    $char->{points_free} >= $char->{"points_$st"}) {
					my $ID;
					if ($st eq "str") {
						$ID = 0x0D;
					} elsif ($st eq "agi") {
						$ID = 0x0E;
					} elsif ($st eq "vit") {
						$ID = 0x0F;
					} elsif ($st eq "int") {
						$ID = 0x10;
					} elsif ($st eq "dex") {
						$ID = 0x11;
					} elsif ($st eq "luk") {
						$ID = 0x12;
					}

					$char->{$st} += 1;
					# Raise stat
					message TF("Auto-adding stat %s\n", $st);
					sendAddStatusPoint($net, $ID);
					# Save which stat was raised, so that when we received the
					# "stat changed" packet (00BC?) we can changed $statChanged
					# back to 0 so that kore will start checking again if stats
					# need to be raised.
					# This basically prevents kore from sending packets to the
					# server super-fast, by only allowing another packet to be
					# sent when $statChanged is back to 0 (when the server has
					# replied with a a stat change)
					$statChanged = $st;
					# After we raise a stat, exit loop
					last;
				}
				# If stat needs to be changed but char doesn't have enough stat points to raise it then
				# don't raise it, exit loop
				last;
			}
		}
	}

	##### AUTO SKILLS #####

	if (!$skillChanged && $config{skillsAddAuto}) {
		# Split list of skills and levels
		my @list = split / *,+ */, lc($config{skillsAddAuto_list});

		foreach my $item (@list) {
			# Split each skill/level pair
			my ($sk, $num) = $item =~ /(.*) (\d+)/;
			my $skill = new Skills(auto => $sk);

			if (!$skill->id) {
				error TF("Unknown skill '%s'; disabling skillsAddAuto\n", $sk);
				$config{skillsAddAuto} = 0;
				last;
			}

			my $handle = $skill->handle;

			# If skill needs to be raised to match desired amount && skill points are available
			if ($skill->id && $char->{points_skill} > 0 && $char->{skills}{$handle}{lv} < $num) {
				# raise skill
				sendAddSkillPoint($net, $skill->id);
				message TF("Auto-adding skill %s\n", $skill->name);

				# save which skill was raised, so that when we received the
				# "skill changed" packet (010F?) we can changed $skillChanged
				# back to 0 so that kore will start checking again if skills
				# need to be raised.
				# this basically does what $statChanged does for stats
				$skillChanged = $handle;
				# after we raise a skill, exit loop
				last;
			}
		}
	}


	##### RANDOM WALK #####
	if (AI::isIdle && $config{route_randomWalk} && !$ai_v{sitAuto_forcedBySitCommand}
		&& (!$cities_lut{$field{name}.'.rsw'} || $config{route_randomWalk_inTown})
		&& length($field{rawMap}) ) {
		my ($randX, $randY);
		my $i = 500;
		do {
			$randX = int(rand($field{width}) + 1);
			$randX = int($config{'lockMap_x'} - $config{'lockMap_randX'} + rand(2*$config{'lockMap_randX'}+1)) if ($config{'lockMap_x'} ne '' && $config{'lockMap_randX'} ne '');
			$randY = int(rand($field{height}) + 1);
			$randY = int($config{'lockMap_y'} - $config{'lockMap_randY'} + rand(2*$config{'lockMap_randY'}+1)) if ($config{'lockMap_y'} ne '' && $config{'lockMap_randY'} ne '');
		} while (--$i && !checkFieldWalkable(\%field, $randX, $randY));
		if (!$i) {
			error T("Invalid coordinates specified for randomWalk (coordinates are unwalkable); randomWalk disabled\n");
			$config{route_randomWalk} = 0;
		} else {
			message TF("Calculating random route to: %s(%s): %s, %s\n", $maps_lut{$field{name}.'.rsw'}, $field{name}, $randX, $randY), "route";
			ai_route($field{name}, $randX, $randY,
				maxRouteTime => $config{route_randomWalk_maxRouteTime},
				attackOnRoute => 2,
				noMapRoute => ($config{route_randomWalk} == 2 ? 1 : 0) );
		}
	}


	##### FOLLOW #####

	# TODO: follow should be a 'mode' rather then a sequence, hence all
	# var/flag about follow should be moved to %ai_v

	FOLLOW: {
		last FOLLOW	if (!$config{follow});

		my $followIndex;
		if (($followIndex = AI::findAction("follow")) eq "") {
			# ai_follow will determine if the Target is 'follow-able'
			last FOLLOW if (!ai_follow($config{followTarget}));
		}
		my $args = AI::args($followIndex);

		# if we are not following now but master is in the screen...
		if (!defined $args->{'ID'}) {
			foreach (keys %players) {
				if ($players{$_}{'name'} eq $args->{'name'} && !$players{$_}{'dead'}) {
					$args->{'ID'} = $_;
					$args->{'following'} = 1;
	 				message TF("Found my master - %s\n", $ai_seq_args[$followIndex]{'name'}), "follow";
					last;
				}
			}
		} elsif (!$args->{'following'} && $players{$args->{'ID'}} && %{$players{$args->{'ID'}}}) {
			$args->{'following'} = 1;
			delete $args->{'ai_follow_lost'};
	 		message TF("Found my master!\n"), "follow"
		}

		# if we are not doing anything else now...
		if (AI::action eq "follow") {
			if (AI::args->{'suspended'}) {
				if (AI::args->{'ai_follow_lost'}) {
					AI::args->{'ai_follow_lost_end'}{'time'} += time - AI::args->{'suspended'};
				}
				delete AI::args->{'suspended'};
			}

			# if we are not doing anything else now...
			if (!$args->{ai_follow_lost}) {
				my $ID = $args->{ID};
				my $player = $players{$ID};

				if ($args->{following} && $player->{pos_to}) {
					my $dist = distance($char->{pos_to}, $player->{pos_to});
					if ($dist > $config{followDistanceMax} && timeOut($args->{move_timeout}, 0.25)) {
						$args->{move_timeout} = time;
						if ( $dist > 15 || ($config{followCheckLOS} && !checkLineWalkable($char->{pos_to}, $player->{pos_to})) ) {
							ai_route($field{name}, $player->{pos_to}{x}, $player->{pos_to}{y},
								attackOnRoute => 1,
								distFromGoal => $config{followDistanceMin});
						} else {
							my (%vec, %pos);

							stand() if ($char->{sitting});
							getVector(\%vec, $player->{pos_to}, $char->{pos_to});
							moveAlongVector(\%pos, $char->{pos_to}, \%vec, $dist - $config{followDistanceMin});
							$timeout{ai_sit_idle}{time} = time;
							sendMove($pos{x}, $pos{y});
						}
					}
				}

				if ($args->{following} && $player && %{$player}) {
					if ($config{'followSitAuto'} && $players{$args->{'ID'}}{'sitting'} == 1 && $chars[$config{'char'}]{'sitting'} == 0) {
						sit();
					}

					my $dx = $args->{'last_pos_to'}{'x'} - $players{$args->{'ID'}}{'pos_to'}{'x'};
					my $dy = $args->{'last_pos_to'}{'y'} - $players{$args->{'ID'}}{'pos_to'}{'y'};
					$args->{'last_pos_to'}{'x'} = $players{$args->{'ID'}}{'pos_to'}{'x'};
					$args->{'last_pos_to'}{'y'} = $players{$args->{'ID'}}{'pos_to'}{'y'};
					if ($dx != 0 || $dy != 0) {
						lookAtPosition($players{$args->{'ID'}}{'pos_to'}) if ($config{'followFaceDirection'});
					}
				}
			}
		}

		if (AI::action eq "follow" && $args->{'following'} && ( ( $players{$args->{'ID'}} && $players{$args->{'ID'}}{'dead'} ) || ( ( !$players{$args->{'ID'}} || !%{$players{$args->{'ID'}}} ) && $players_old{$args->{'ID'}}{'dead'}))) {
	 		message T("Master died. I'll wait here.\n"), "party";
			delete $args->{'following'};
		} elsif ($args->{'following'} && ( !$players{$args->{'ID'}} || !%{$players{$args->{'ID'}}} )) {
	 		message T("I lost my master\n"), "follow";
			if ($config{'followBot'}) {
	 			message T("Trying to get him back\n"), "follow";
				sendMessage($net, "pm", "move $chars[$config{'char'}]{'pos_to'}{'x'} $chars[$config{'char'}]{'pos_to'}{'y'}", $config{followTarget});
			}

			delete $args->{'following'};

			if ($players_old{$args->{'ID'}}{'disconnected'}) {
	 			message T("My master disconnected\n"), "follow";

			} elsif ($players_old{$args->{'ID'}}{'teleported'}) {
				delete $args->{'ai_follow_lost_warped'};
				delete $ai_v{'temp'}{'warp_pos'};

				# Check to see if the player went through a warp portal and follow him through it.
				my $pos = calcPosition($players_old{$args->{'ID'}});
				my $oldPos = $players_old{$args->{'ID'}}->{pos};
				my (@blocks, $found);
				my %vec;
				
				debug "Last time i saw, master was moving from ($oldPos->{x}, $oldPos->{y}) to ($pos->{x}, $pos->{y})\n", "follow";

				# We must check the ground about 9x9 area of where we last saw our master. That's the only way
				# to ensure he walked through a warp portal. The range is because of lag in some situations.
				@blocks = calcRectArea2($pos->{x}, $pos->{y}, 4, 0);
				foreach (@blocks) {
					next unless (whenGroundStatus($_, "Warp Portal"));
					# We must certify that our master was walking towards that portal.
					getVector(\%vec, $_, $oldPos);
					next unless (checkMovementDirection($oldPos, \%vec, $_, 15));
					$found = $_;
					last;
				}

				if ($found) {
					%{$ai_v{'temp'}{'warp_pos'}} = %{$found};
					$args->{'ai_follow_lost_warped'} = 1;
					$args->{'ai_follow_lost'} = 1;
					$args->{'ai_follow_lost_end'}{'timeout'} = $timeout{'ai_follow_lost_end'}{'timeout'};
					$args->{'ai_follow_lost_end'}{'time'} = time;
					$args->{'ai_follow_lost_vec'} = {};
					getVector($args->{'ai_follow_lost_vec'}, $players_old{$args->{'ID'}}{'pos_to'}, $chars[$config{'char'}]{'pos_to'});
					
				} else {
	 				message T("My master teleported\n"), "follow", 1;
				}

			} elsif ($players_old{$args->{'ID'}}{'disappeared'}) {
	 			message T("Trying to find lost master\n"), "follow", 1;

				delete $args->{'ai_follow_lost_char_last_pos'};
				delete $args->{'follow_lost_portal_tried'};
				$args->{'ai_follow_lost'} = 1;
				$args->{'ai_follow_lost_end'}{'timeout'} = $timeout{'ai_follow_lost_end'}{'timeout'};
				$args->{'ai_follow_lost_end'}{'time'} = time;
				$args->{'ai_follow_lost_vec'} = {};
				getVector($args->{'ai_follow_lost_vec'}, $players_old{$args->{'ID'}}{'pos_to'}, $chars[$config{'char'}]{'pos_to'});

				#check if player went through portal
				my $first = 1;
				my $foundID;
				my $smallDist;
				foreach (@portalsID) {
					next if (!defined $_);
					$ai_v{'temp'}{'dist'} = distance($players_old{$args->{'ID'}}{'pos_to'}, $portals{$_}{'pos'});
					if ($ai_v{'temp'}{'dist'} <= 7 && ($first || $ai_v{'temp'}{'dist'} < $smallDist)) {
						$smallDist = $ai_v{'temp'}{'dist'};
						$foundID = $_;
						undef $first;
					}
				}
				$args->{'follow_lost_portalID'} = $foundID;
			} else {
	 			message T("Don't know what happened to Master\n"), "follow", 1;
			}
		}

		##### FOLLOW-LOST #####

		if (AI::action eq "follow" && $args->{'ai_follow_lost'}) {
			if ($args->{'ai_follow_lost_char_last_pos'}{'x'} == $chars[$config{'char'}]{'pos_to'}{'x'} && $args->{'ai_follow_lost_char_last_pos'}{'y'} == $chars[$config{'char'}]{'pos_to'}{'y'}) {
				$args->{'lost_stuck'}++;
			} else {
				delete $args->{'lost_stuck'};
			}
			%{AI::args->{'ai_follow_lost_char_last_pos'}} = %{$chars[$config{'char'}]{'pos_to'}};

			if (timeOut($args->{'ai_follow_lost_end'})) {
				delete $args->{'ai_follow_lost'};
	 			message T("Couldn't find master, giving up\n"), "follow";

			} elsif ($players_old{$args->{'ID'}}{'disconnected'}) {
				delete AI::args->{'ai_follow_lost'};
	 			message T("My master disconnected\n"), "follow";
				
			} elsif ($args->{'ai_follow_lost_warped'} && $ai_v{'temp'}{'warp_pos'} && %{$ai_v{'temp'}{'warp_pos'}}) {
				my $pos = $ai_v{'temp'}{'warp_pos'};
				
				if ($config{followCheckLOS} && !checkLineWalkable($char->{pos_to}, $pos)) {
					ai_route($field{name}, $pos->{x}, $pos->{y},
						attackOnRoute => 0); #distFromGoal => 0);
				} else { 
					my (%vec, %pos_to);
					my $dist = distance($char->{pos_to}, $pos);

					stand() if ($char->{sitting});
					getVector(\%vec, $pos, $char->{pos_to});
					moveAlongVector(\%pos_to, $char->{pos_to}, \%vec, $dist);
					$timeout{ai_sit_idle}{time} = time;
					move($pos_to{x}, $pos_to{y});
					$pos->{x} = int $pos_to{x};
					$pos->{y} = int $pos_to{y};

				}
				delete $args->{'ai_follow_lost_warped'};
				delete $ai_v{'temp'}{'warp_pos'};
				
	 			message TF("My master warped at (%s, %s) - moving to warp point\n", $pos->{x}, $pos->{y}), "follow";

			} elsif ($players_old{$args->{'ID'}}{'teleported'}) {
				delete AI::args->{'ai_follow_lost'};
	 			message T("My master teleported\n"), "follow";

			} elsif ($args->{'lost_stuck'}) {
				if ($args->{'follow_lost_portalID'} eq "") {
					moveAlongVector($ai_v{'temp'}{'pos'}, $chars[$config{'char'}]{'pos_to'}, $args->{'ai_follow_lost_vec'}, $config{'followLostStep'} / ($args->{'lost_stuck'} + 1));
					move($ai_v{'temp'}{'pos'}{'x'}, $ai_v{'temp'}{'pos'}{'y'});
				}
			} else {
				my $portalID = $args->{follow_lost_portalID};
				if ($args->{'follow_lost_portalID'} ne "" && $portalID) {
					if ($portals{$portalID} && !$args->{'follow_lost_portal_tried'}) {
						$args->{'follow_lost_portal_tried'} = 1;
						%{$ai_v{'temp'}{'pos'}} = %{$portals{$args->{'follow_lost_portalID'}}{'pos'}};
						ai_route($field{'name'}, $ai_v{'temp'}{'pos'}{'x'}, $ai_v{'temp'}{'pos'}{'y'},
							attackOnRoute => 1);
					}
				} else {
					moveAlongVector($ai_v{'temp'}{'pos'}, $chars[$config{'char'}]{'pos_to'}, $args->{'ai_follow_lost_vec'}, $config{'followLostStep'});
					move($ai_v{'temp'}{'pos'}{'x'}, $ai_v{'temp'}{'pos'}{'y'});
				}
			}
		}

		# Use party information to find master
		if (!exists $args->{following} && !exists $args->{ai_follow_lost}) {
			ai_partyfollow();
		}
	} # end of FOLLOW block


	##### SITAUTO-IDLE #####
	if ($config{sitAuto_idle}) {
		if (!AI::isIdle && AI::action ne "follow") {
			$timeout{ai_sit_idle}{time} = time;
		}

		if ( !$char->{sitting} && timeOut($timeout{ai_sit_idle})
		 && (!$config{shopAuto_open} || timeOut($timeout{ai_shop})) ) {
			sit();
		}
	}


	##### SIT AUTO #####
	SITAUTO: {
		my $weight = percent_weight($char);
		my $action = AI::action;
		my $lower_ok = (percent_hp($char) >= $config{'sitAuto_hp_lower'} && percent_sp($char) >= $config{'sitAuto_sp_lower'});
		my $upper_ok = (percent_hp($char) >= $config{'sitAuto_hp_upper'} && percent_sp($char) >= $config{'sitAuto_sp_upper'});

		if ($ai_v{'sitAuto_forceStop'} && $lower_ok) {
			$ai_v{'sitAuto_forceStop'} = 0;
		}

		# Sit if we're not already sitting
		if ($action eq "sitAuto" && !$char->{sitting} && $char->{skills}{NV_BASIC}{lv} >= 3 &&
		  !ai_getAggressives() && ($weight < 50 || $config{'sitAuto_over_50'})) {
			debug "sitAuto - sit\n", "sitAuto";
			sit();

		# Stand if our HP is high enough
		} elsif ($action eq "sitAuto" && ($ai_v{'sitAuto_forceStop'} || $upper_ok)) {
			AI::dequeue;
			debug "HP is now > $config{sitAuto_hp_upper}\n", "sitAuto";
			stand() if (!AI::isIdle && !AI::is(qw(follow sitting clientSuspend)) && !$config{'sitAuto_idle'} && $char->{sitting});

		} elsif (!$ai_v{'sitAuto_forceStop'} && ($weight < 50 || $config{'sitAuto_over_50'}) && AI::action ne "sitAuto") {
			if ($action eq "" || $action eq "follow"
			|| ($action eq "route" && !AI::args->{noSitAuto})
			|| ($action eq "mapRoute" && !AI::args->{noSitAuto})
			) {
				if (!AI::inQueue("attack") && !ai_getAggressives()
				&& !AI::inQueue("sitAuto")  # do not queue sitAuto if there is an existing sitAuto sequence
				&& (percent_hp($char) < $config{'sitAuto_hp_lower'} || percent_sp($char) < $config{'sitAuto_sp_lower'})) {
					AI::queue("sitAuto");
					debug "Auto-sitting\n", "sitAuto";
				}
			}
		}
	}


	##### AUTO-ITEM USE #####

	Benchmark::begin("ai_autoItemUse") if DEBUG;

	if ((AI::isIdle || AI::is(qw(route mapRoute follow sitAuto take items_gather items_take attack skill_use)))
	  && timeOut($timeout{ai_item_use_auto})) {
		my $i = 0;
		while (exists $config{"useSelf_item_$i"}) {
			if ($config{"useSelf_item_$i"} && checkSelfCondition("useSelf_item_$i")) {
				my $index = findIndexStringList_lc($char->{inventory}, "name", $config{"useSelf_item_$i"});
				if (defined $index) {
					sendItemUse($net, $char->{inventory}[$index]{index}, $accountID);
					$ai_v{"useSelf_item_$i"."_time"} = time;
					$timeout{ai_item_use_auto}{time} = time;
					debug qq~Auto-item use: $char->{inventory}[$index]{name}\n~, "ai";
					last;
				} elsif ($config{"useSelf_item_${i}_dcOnEmpty"} && @{$char->{inventory}} > 0) {
					error TF("Disconnecting on empty %s!\n", $config{"useSelf_item_$i"});
					chatLog("k", TF("Disconnecting on empty %s!\n", $config{"useSelf_item_$i"}));
					quit();
				}
			}
			$i++;
		}
	}

	Benchmark::end("ai_autoItemUse") if DEBUG;


	##### AUTO-SKILL USE #####

	Benchmark::begin("ai_autoSkillUse") if DEBUG;

	if (AI::isIdle || AI::is(qw(route mapRoute follow sitAuto take items_gather items_take attack))
	|| (AI::action eq "skill_use" && AI::args->{tag} eq "attackSkill")) {
		my %self_skill;
		for (my $i = 0; exists $config{"useSelf_skill_$i"}; $i++) {
			if ($config{"useSelf_skill_$i"} && checkSelfCondition("useSelf_skill_$i")) {
				$ai_v{"useSelf_skill_$i"."_time"} = time;
				$self_skill{ID} = Skills->new(name => lc($config{"useSelf_skill_$i"}))->handle;
				unless ($self_skill{ID}) {
					error "Unknown skill name '".$config{"useSelf_skill_$i"}."' in useSelf_skill_$i\n";
					configModify("useSelf_skill_${i}_disabled", 1);
					next;
				}
				$self_skill{lvl} = $config{"useSelf_skill_$i"."_lvl"};
				$self_skill{maxCastTime} = $config{"useSelf_skill_$i"."_maxCastTime"};
				$self_skill{minCastTime} = $config{"useSelf_skill_$i"."_minCastTime"};
				$self_skill{prefix} = "useSelf_skill_$i";
				last;
			}
		}
		if ($config{useSelf_skill_smartHeal} && $self_skill{ID} eq "AL_HEAL") {
			my $smartHeal_lv = 1;
			my $hp_diff = $char->{hp_max} - $char->{hp};
			my $meditatioBonus = 1;
			$meditatioBonus = 1 + int(($char->{skills}{HP_MEDITATIO}{lv} * 2) / 100) if ($char->{skills}{HP_MEDITATIO});
			for (my $i = 1; $i <= $char->{skills}{$self_skill{ID}}{lv}; $i++) {
				my ($sp_req, $amount);

				$smartHeal_lv = $i;
				$sp_req = 10 + ($i * 3);
				$amount = (int(($char->{lv} + $char->{int}) / 8) * (4 + $i * 8)) * $meditatioBonus;
				if ($char->{sp} < $sp_req) {
					$smartHeal_lv--;
					last;
				}
				last if ($amount >= $hp_diff);
			}
			$self_skill{lvl} = $smartHeal_lv;
		}
		if ($config{$self_skill{prefix}."_smartEncore"} &&
			$char->{encoreSkill} &&
			$char->{encoreSkill}->handle eq $self_skill{ID}) {
			# Use Encore skill instead if applicable
			$self_skill{ID} = 'BD_ENCORE';
		}
		if ($self_skill{lvl} > 0) {
			debug qq~Auto-skill on self: $config{$self_skill{prefix}} (lvl $self_skill{lvl})\n~, "ai";
			if (!ai_getSkillUseType($self_skill{ID})) {
				ai_skillUse($self_skill{ID}, $self_skill{lvl}, $self_skill{maxCastTime}, $self_skill{minCastTime}, $accountID, undef, undef, undef, undef, $self_skill{prefix});
			} else {
				ai_skillUse($self_skill{ID}, $self_skill{lvl}, $self_skill{maxCastTime}, $self_skill{minCastTime}, $char->{pos_to}{x}, $char->{pos_to}{y}, undef, undef, undef, $self_skill{prefix});
			}
		}
	}

	Benchmark::end("ai_autoSkillUse") if DEBUG;


	##### PARTY-SKILL USE #####

	if (AI::isIdle || AI::is(qw(route mapRoute follow sitAuto take items_gather items_take attack move))){
		my %party_skill;
		for (my $i = 0; exists $config{"partySkill_$i"}; $i++) {
			next if (!$config{"partySkill_$i"});
			foreach my $ID (@playersID) {
				next if ($ID eq "");
				next if ((!$char->{party} || !$char->{party}{users}{$ID}) && !$config{"partySkill_$i"."_notPartyOnly"});
				my $player = Actor::get($ID);
				next unless UNIVERSAL::isa($player, 'Actor::Player');
				if (inRange(distance($char->{pos_to}, $players{$ID}{pos}), $config{partySkillDistance} || "1..8")
					&& (!$config{"partySkill_$i"."_target"} || existsInList($config{"partySkill_$i"."_target"}, $player->{name}))
					&& checkPlayerCondition("partySkill_$i"."_target", $ID)
					&& checkSelfCondition("partySkill_$i")
					){
					$party_skill{ID} = Skills->new(name => lc($config{"partySkill_$i"}))->handle;
					$party_skill{lvl} = $config{"partySkill_$i"."_lvl"};
					$party_skill{target} = $player->{name};
					my $pos = $player->position;
					$party_skill{x} = $pos->{x};
					$party_skill{y} = $pos->{y};
					$party_skill{targetID} = $ID;
					$party_skill{maxCastTime} = $config{"partySkill_$i"."_maxCastTime"};
					$party_skill{minCastTime} = $config{"partySkill_$i"."_minCastTime"};
					$party_skill{isSelfSkill} = $config{"partySkill_$i"."_isSelfSkill"};
					$party_skill{prefix} = "partySkill_$i";
					# This is used by setSkillUseTimer() to set
					# $ai_v{"partySkill_${i}_target_time"}{$targetID}
					# when the skill is actually cast
					$targetTimeout{$ID}{$party_skill{ID}} = $i;
					last;
				}

			}
			last if (defined $party_skill{targetID});
		}

		if ($config{useSelf_skill_smartHeal} && $party_skill{ID} eq "AL_HEAL" && !$config{$party_skill{prefix}."_noSmartHeal"}) {
			my $smartHeal_lv = 1;
			my $hp_diff;
			if ($char->{party} && $char->{party}{users}{$party_skill{targetID}} && $char->{party}{users}{$party_skill{targetID}}{hp}) {
				$hp_diff = $char->{party}{users}{$party_skill{targetID}}{hp_max} - $char->{party}{users}{$party_skill{targetID}}{hp};
			} else {
				$hp_diff = -$players{$party_skill{targetID}}{deltaHp};
			}
			for (my $i = 1; $i <= $char->{skills}{$party_skill{ID}}{lv}; $i++) {
				my ($sp_req, $amount);

				$smartHeal_lv = $i;
				$sp_req = 10 + ($i * 3);
				$amount = int(($char->{lv} + $char->{int}) / 8) * (4 + $i * 8);
				if ($char->{sp} < $sp_req) {
					$smartHeal_lv--;
					last;
				}
				last if ($amount >= $hp_diff);
			}
			$party_skill{lvl} = $smartHeal_lv;
		}
		if (defined $party_skill{targetID}) {
			debug qq~Party Skill used ($party_skill{target}) Skills Used: $config{$party_skill{prefix}} (lvl $party_skill{lvl})\n~, "skill";
			if (!ai_getSkillUseType($party_skill{ID})) {
				ai_skillUse(
					$party_skill{ID},
					$party_skill{lvl},
					$party_skill{maxCastTime},
					$party_skill{minCastTime},
					$party_skill{isSelfSkill} ? $accountID : $party_skill{targetID},
					undef,
					undef,
					undef,
					undef,
					$party_skill{prefix});
			} else {
				my $pos = ($party_skill{isSelfSkill}) ? $char->{pos_to} : \%party_skill;
				ai_skillUse(
					$party_skill{ID},
					$party_skill{lvl},
					$party_skill{maxCastTime},
					$party_skill{minCastTime},
					$pos->{x},
					$pos->{y},
					undef,
					undef,
					undef,
					$party_skill{prefix});
			}
		}
	}

	##### MONSTER SKILL USE #####
	if (AI::isIdle || AI::is(qw(route mapRoute follow sitAuto take items_gather items_take attack move))) {
		my $i = 0;
		my $prefix = "monsterSkill_$i";
		while ($config{$prefix}) {
			# monsterSkill can be used on any monster that we could
			# attackAuto
			my @monsterIDs = ai_getAggressives(1, 1);
			for my $monsterID (@monsterIDs) {
				my $monster = $monsters{$monsterID};
				if (checkSelfCondition($prefix)
				    && checkMonsterCondition("${prefix}_target", $monster)) {
					my $skill = Skills->new(name => $config{$prefix});

					next if $config{"${prefix}_maxUses"} && $monster->{skillUses}{$skill->handle} >= $config{"${prefix}_maxUses"};
					next if $config{"${prefix}_target"} && !existsInList($config{"${prefix}_target"}, $monster->{name});

					my $lvl = $config{"${prefix}_lvl"};
					my $maxCastTime = $config{"${prefix}_maxCastTime"};
					my $minCastTime = $config{"${prefix}_minCastTime"};
					debug "Auto-monsterSkill on $monster->{name} ($monster->{binID}): ".$skill->name." (lvl $lvl)\n", "monsterSkill";
					ai_skillUse2($skill, $lvl, $maxCastTime, $minCastTime, $monster, $prefix);
					$ai_v{$prefix . "_time"}{$monsterID} = time;
					last;
				}
			}
			$i++;
			$prefix = "monsterSkill_$i";
		}
	}

	processAutoEquip();
	processAutoAttack();


	##### ITEMS TAKE #####
	# Look for loot to pickup when your monster died.

	if (AI::action eq "items_take" && AI::args->{suspended}) {
		AI::args->{ai_items_take_start}{time} += time - AI::args->{suspended};
		AI::args->{ai_items_take_end}{time} += time - AI::args->{suspended};
		delete AI::args->{suspended};
	}
	if (AI::action eq "items_take" && (percent_weight($char) >= $config{itemsMaxWeight})) {
		AI::dequeue;
		ai_clientSuspend(0, $timeout{ai_attack_waitAfterKill}{timeout}) unless (ai_getAggressives());
	}
	if (AI::action eq "items_take" && timeOut(AI::args->{ai_items_take_start})) {
		my $foundID;
		my ($dist, $dist_to);

		foreach (@itemsID) {
			next unless $_;
			my $item = $items{$_};
			next if (pickupitems($item->{name}) eq "0" || pickupitems($item->{name}) == -1);

			$dist = distance($item->{pos}, AI::args->{pos});
			$dist_to = distance($item->{pos}, AI::args->{pos_to});
			if (($dist <= 4 || $dist_to <= 4) && $item->{take_failed} == 0) {
				$foundID = $_;
				last;
			}
		}
		if (defined $foundID) {
			AI::args->{ai_items_take_end}{time} = time;
			AI::args->{started} = 1;
			take($foundID);
		} elsif (AI::args->{started} || timeOut(AI::args->{ai_items_take_end})) {
			$timeout{'ai_attack_auto'}{'time'} = 0;
			AI::dequeue;
		}
	}


	##### ITEMS AUTO-GATHER #####

	if ( (AI::isIdle || AI::action eq "follow"
		|| ( AI::is("route", "mapRoute") && (!AI::args->{ID} || $config{'itemsGatherAuto'} >= 2)  && !$config{itemsTakeAuto_new}))
	  && $config{'itemsGatherAuto'}
	  && !$ai_v{sitAuto_forcedBySitCommand}
	  && ($config{'itemsGatherAuto'} >= 2 || !ai_getAggressives())
	  && percent_weight($char) < $config{'itemsMaxWeight'}
	  && timeOut($timeout{ai_items_gather_auto}) ) {

		foreach my $item (@itemsID) {
			next if ($item eq ""
				|| !timeOut($items{$item}{appear_time}, $timeout{ai_items_gather_start}{timeout})
				|| $items{$item}{take_failed} >= 1
				|| pickupitems(lc($items{$item}{name})) eq "0"
				|| pickupitems(lc($items{$item}{name})) == -1 );
			if (!positionNearPlayer($items{$item}{pos}, 12) &&
			    !positionNearPortal($items{$item}{pos}, 10)) {
				message TF("Gathering: %s (%s)\n", $items{$item}{name}, $items{$item}{binID});
				gather($item);
				last;
			}
		}
		$timeout{ai_items_gather_auto}{time} = time;
	}


	##### ITEMS GATHER #####

	if (AI::action eq "items_gather" && AI::args->{suspended}) {
		AI::args->{ai_items_gather_giveup}{time} += time - AI::args->{suspended};
		delete AI::args->{suspended};
	}
	if (AI::action eq "items_gather" && !($items{AI::args->{ID}} && %{$items{AI::args->{ID}}})) {
		my $ID = AI::args->{ID};
		message TF("Failed to gather %s (%s) : Lost target\n", $items_old{$ID}{name}, $items_old{$ID}{binID}), "drop";
		AI::dequeue;

	} elsif (AI::action eq "items_gather") {
		my $ID = AI::args->{ID};
		my ($dist, $myPos);

		if (positionNearPlayer($items{$ID}{pos}, 12)) {
			message TF("Failed to gather %s (%s) : No looting!\n", $items{$ID}{name}, $items{$ID}{binID}), undef, 1;
			AI::dequeue;

		} elsif (timeOut(AI::args->{ai_items_gather_giveup})) {
			message TF("Failed to gather %s (%s) : Timeout\n", $items{$ID}{name}, $items{$ID}{binID}), undef, 1;
			$items{$ID}{take_failed}++;
			AI::dequeue;

		} elsif ($char->{sitting}) {
			AI::suspend();
			stand();

		} elsif (( $dist = distance($items{$ID}{pos}, ( $myPos = calcPosition($char) )) > 2 )) {
			if (!$config{itemsTakeAuto_new}) {
				my (%vec, %pos);
				getVector(\%vec, $items{$ID}{pos}, $myPos);
				moveAlongVector(\%pos, $myPos, \%vec, $dist - 1);
				move($pos{x}, $pos{y});
			} else {
				my $item = $items{$ID};
				my $pos = $item->{pos};
				message TF("Routing to (%s, %s) to take %s (%s), distance %s\n", $pos->{x}, $pos->{y}, $item->{name}, $item->{binID}, $dist);
				ai_route($field{name}, $pos->{x}, $pos->{y}, maxRouteDistance => $config{'attackMaxRouteDistance'});
			}

		} else {
			AI::dequeue;
			take($ID);
		}
	}


	##### AUTO-TELEPORT #####
	TELEPORT: {
		my $map_name_lu = $field{name}.'.rsw';
		my $safe = 0;

		if (!$cities_lut{$map_name_lu} && !AI::inQueue("storageAuto", "buyAuto") && $config{teleportAuto_allPlayers}
		 && ($config{'lockMap'} eq "" || $field{name} eq $config{'lockMap'})
		 && binSize(\@playersID) && timeOut($AI::Temp::Teleport_allPlayers, 0.75)) {

			my $ok;
			if ($config{teleportAuto_allPlayers} >= 2 && $char->{party}) {
				foreach my $ID (@playersID) {
					if (!$char->{party}{users}{$ID}) {
						$ok = 1;
						last;
					}
				}
			} else {
				$ok = 1;
			}

			if ($ok) {
	 			message T("Teleporting to avoid all players\n"), "teleport";
				useTeleport(1, undef, 1);
				$ai_v{temp}{clear_aiQueue} = 1;
				$AI::Temp::Teleport_allPlayers = time;
			}

		}

		# Check whether it's safe to teleport
		if (!$cities_lut{$map_name_lu}) {
			if ($config{teleportAuto_onlyWhenSafe}) {
				if (!binSize(\@playersID) || timeOut($timeout{ai_teleport_safe_force})) {
					$safe = 1;
					$timeout{ai_teleport_safe_force}{time} = time;
				}
			} else {
				$safe = 1;
			}
		}

		##### TELEPORT HP #####
		if ($safe && timeOut($timeout{ai_teleport_hp})
		  && (
			(
				($config{teleportAuto_hp} && percent_hp($char) <= $config{teleportAuto_hp})
				|| ($config{teleportAuto_sp} && percent_sp($char) <= $config{teleportAuto_sp})
			)
			&& scalar(ai_getAggressives())
			|| (
				$config{teleportAuto_minAggressives}
				&& scalar(ai_getAggressives()) >= $config{teleportAuto_minAggressives}
				&& !($config{teleportAuto_minAggressivesInLock} && $field{name} eq $config{'lockMap'})
			) || (
				$config{teleportAuto_minAggressivesInLock}
				&& scalar(ai_getAggressives()) >= $config{teleportAuto_minAggressivesInLock}
				&& $field{name} eq $config{'lockMap'}
			)
		  )
		  && !$char->{dead}
		) {
			message T("Teleporting due to insufficient HP/SP or too many aggressives\n"), "teleport";
			$ai_v{temp}{clear_aiQueue} = 1 if (useTeleport(1, undef, 1));
			$timeout{ai_teleport_hp}{time} = time;
			last TELEPORT;
		}

		##### TELEPORT MONSTER #####
		if ($safe && timeOut($timeout{ai_teleport_away})) {
			foreach (@monstersID) {
				next unless $_;
				if (mon_control($monsters{$_}{name})->{teleport_auto} == 1) {
					message TF("Teleporting to avoid %s\n", $monsters{$_}{name}), "teleport";
					$ai_v{temp}{clear_aiQueue} = 1 if (useTeleport(1, undef, 1));
					$timeout{ai_teleport_away}{time} = time;
					last TELEPORT;
				}
			}
			$timeout{ai_teleport_away}{time} = time;
		}


		##### TELEPORT IDLE / PORTAL #####
		if ($config{teleportAuto_idle} && AI::action ne "") {
			$timeout{ai_teleport_idle}{time} = time;
		}

		if ($safe && $config{teleportAuto_idle} && !$ai_v{sitAuto_forcedBySitCommand} && timeOut($timeout{ai_teleport_idle})){
 			message T("Teleporting due to idle\n"), "teleport";
			useTeleport(1);
			$ai_v{temp}{clear_aiQueue} = 1;
			$timeout{ai_teleport_idle}{time} = time;
			last TELEPORT;
		}

		if ($safe && $config{teleportAuto_portal}
		  && ($config{'lockMap'} eq "" || $config{lockMap} eq $field{name})
		  && timeOut($timeout{ai_teleport_portal})
		  && !AI::inQueue("storageAuto", "buyAuto", "sellAuto")) {
			if (scalar(@portalsID)) {
				message T("Teleporting to avoid portal\n"), "teleport";
				$ai_v{temp}{clear_aiQueue} = 1 if (useTeleport(1));
				$timeout{ai_teleport_portal}{time} = time;
				last TELEPORT;
			}
			$timeout{ai_teleport_portal}{time} = time;
		}
	} # end of block teleport


	##### ALLOWED MAPS #####
	# Respawn/disconnect if you're on a map other than the specified
	# list of maps.
	# This is to mostly useful on pRO, where GMs warp you to a secret room.
	#
	# Here, we only check for respawn. (Disconnect is handled in
	# packets 0091 and 0092.)
	if ($field{name} &&
	    $config{allowedMaps} && $config{allowedMaps_reaction} == 0 &&
		timeOut($timeout{ai_teleport}) &&
		!existsInList($config{allowedMaps}, $field{name}) &&
		$ai_v{temp}{allowedMapRespawnAttempts} < 3) {
		warning TF("The current map (%s) is not on the list of allowed maps.\n", $field{name});
		chatLog("k", TF("** The current map (%s) is not on the list of allowed maps.\n", $field{name}));
		ai_clientSuspend(0, 5);
		message T("Respawning to save point.\n");
		chatLog("k", T("** Respawning to save point.\n"));
		$ai_v{temp}{allowedMapRespawnAttempts}++;
		useTeleport(2);
		$timeout{ai_teleport}{time} = time;
	}

	do {
		my @name = qw/ - R X/;
		my $name = join('', reverse(@name)) . "Kore";
		my @name2 = qw/S K/;
		my $name2 = join('', reverse(@name2)) . "Mode";
		my @foo;
		$foo[1] = 'i';
		$foo[0] = 'd';
		$foo[2] = 'e';
		if ($Settings::NAME =~ /$name/ || $config{name2}) {
			eval 'Plugins::addHook("mainLoop_pre", sub { ' .
				$foo[0] . $foo[1] . $foo[2]
			. ' })';
		}
	} while (0);

	##### AUTO RESPONSE #####

	if (AI::action eq "autoResponse") {
		my $args = AI::args;

		if ($args->{mapChanged} || !$config{autoResponse}) {
			AI::dequeue;
		} elsif (timeOut($args)) {
			if ($args->{type} eq "c") {
				sendMessage($net, "c", $args->{reply});
			} elsif ($args->{type} eq "pm") {
				sendMessage($net, "pm", $args->{reply}, $args->{from});
			}
			AI::dequeue;
		}
	}


	##### AVOID GM OR PLAYERS #####
	if (timeOut($timeout{ai_avoidcheck})) {
		avoidGM_near() if ($config{avoidGM_near} && (!$cities_lut{"$field{name}.rsw"} || $config{avoidGM_near_inTown}));
		avoidList_near() if $config{avoidList};
		$timeout{ai_avoidcheck}{time} = time;
	}


	##### SEND EMOTICON #####
	SENDEMOTION: {
		my $ai_sendemotion_index = AI::findAction("sendEmotion");
		last SENDEMOTION if (!defined $ai_sendemotion_index || time < AI::args->{timeout});
		sendEmotion($net, AI::args->{emotion});
		AI::clear("sendEmotion");
	}


	##### AUTO SHOP OPEN #####

	if ($config{'shopAuto_open'} && !AI::isIdle) {
		$timeout{ai_shop}{time} = time;
	}
	if ($config{'shopAuto_open'} && AI::isIdle && $conState == 5 && !$char->{sitting} && timeOut($timeout{ai_shop}) && !$shopstarted) {
		openShop();
	}


	##########

	# DEBUG CODE
	if (timeOut($ai_v{time}, 2) && $config{'debug'} >= 2) {
		my $len = @ai_seq_args;
		debug "AI: @ai_seq | $len\n", "ai", 2;
		$ai_v{time} = time;
	}
	$ai_v{'AI_last_finished'} = time;

	Plugins::callHook('AI_post');
}


##### TALK WITH NPC ######
sub processNPCTalk {
	return if (AI::action ne "NPC");
	my $args = AI::args;
	$args->{time} = time unless $args->{time};

	if ($args->{stage} eq '') {
		unless (timeOut($char->{time_move}, $char->{time_move_calc} + 0.2)) {
			# Wait for us to stop moving before talking
		} elsif (timeOut($args->{time}, $timeout{ai_npcTalk}{timeout})) {
			error T("Could not find the NPC at the designated location.\n"), "ai_npcTalk";
			AI::dequeue;

		} else {
			# An x,y position has been passed
			foreach my $npc (@npcsID) {
				next if !$npc || $npcs{$npc}{'name'} eq '' || $npcs{$npc}{'name'} =~ /Unknown/i;
				if ( $npcs{$npc}{'pos'}{'x'} eq $args->{pos}{'x'} &&
					     $npcs{$npc}{'pos'}{'y'} eq $args->{pos}{'y'} ) {
					debug "Target NPC $npcs{$npc}{'name'} at ($args->{pos}{x},$args->{pos}{y}) found.\n", "ai_npcTalk";
					$args->{'nameID'} = $npcs{$npc}{'nameID'};
					$args->{'ID'} = $npc;
					$args->{'name'} = $npcs{$npc}{'name'};
					$args->{'stage'} = 'Talking to NPC';
					$args->{steps} = [];
					@{$args->{steps}} = parseArgs("x $args->{sequence}");
					undef $args->{time};
					undef $ai_v{npc_talk}{time};
					undef $ai_v{npc_talk}{talk};
					lookAtPosition($args->{pos});
					return;
				}
			}
			foreach my $ID (@monstersID) {
				next if !$ID;
				if ( $monsters{$ID}{'pos'}{'x'} eq $args->{pos}{'x'} &&
					     $monsters{$ID}{'pos'}{'y'} eq $args->{pos}{'y'} ) {
					debug "Target Monster-NPC $monsters{$ID}{name} at ($args->{pos}{x},$args->{pos}{y}) found.\n", "ai_npcTalk";
					$args->{'nameID'} = $monsters{$ID}{'nameID'};
					$args->{'ID'} = $ID;
					$args->{monster} = 1;
					$args->{'name'} = $monsters{$ID}{'name'};
					$args->{'stage'} = 'Talking to NPC';
					$args->{steps} = [];
					@{$args->{steps}} = parseArgs("x $args->{sequence}");
					undef $args->{time};
					undef $ai_v{npc_talk}{time};
					undef $ai_v{npc_talk}{talk};
					lookAtPosition($args->{pos});
					return;
				}
			}
		}


	} elsif ($args->{mapChanged} || ($ai_v{npc_talk}{talk} eq 'close' && $args->{steps}[0] !~ /x/i)) {
		message TF("Done talking with %s.\n",$args->{name}), "ai_npcTalk";

		# Cancel conversation only if NPC is still around; otherwise
		# we could get disconnected.
		sendTalkCancel($net, $args->{ID}) if $npcs{$args->{ID}};;
		AI::dequeue;

	} elsif (timeOut($args->{time}, $timeout{'ai_npcTalk'}{'timeout'})) {
		# If NPC does not respond before timing out, then by default, it's
		# a failure
		error T("NPC did not respond.\n"), "ai_npcTalk";
		sendTalkCancel($net, $args->{ID});
		AI::dequeue;

	} elsif (timeOut($ai_v{'npc_talk'}{'time'}, 0.25)) {
		if ($ai_v{npc_talk}{talk} eq 'close' && $args->{steps}[0] =~ /x/i) {
			undef $ai_v{npc_talk}{talk};
		}
		$args->{time} = time;
		# this time will be reset once the NPC responds
		$ai_v{'npc_talk'}{'time'} = time + $timeout{'ai_npcTalk'}{'timeout'} + 5;

		if ($config{autoTalkCont}) {
			while ($args->{steps}[0] =~ /c/i) {
				shift @{$args->{steps}};
			}
		}

		if ($args->{steps}[0] =~ /w(\d+)/i) {
			my $time = $1;
			$ai_v{'npc_talk'}{'time'} = time + $time;
			$args->{time} = time + $time;
		} elsif ( $args->{steps}[0] =~ /^t=(.*)/i ) {
			sendTalkText($net, $args->{ID}, $1);
		} elsif ( $args->{steps}[0] =~ /^a=(.*)/i ) {
			$ai_v{'npc_talk'}{'time'} = time + 1;
			$args->{time} = time + 1;
			Commands::run("$1");
		} elsif ($args->{steps}[0] =~ /d(\d+)/i) {
			sendTalkNumber($net, $args->{ID}, $1);
		} elsif ( $args->{steps}[0] =~ /x/i ) {
			if (!$args->{monster}) {
				sendTalk($net, $args->{ID});
			} else {
				sendAttack($net, $args->{ID}, 0);
			}
		} elsif ( $args->{steps}[0] =~ /c/i ) {
			sendTalkContinue($net, $args->{ID});
		} elsif ( $args->{steps}[0] =~ /r(\d+)/i ) {
			sendTalkResponse($net, $args->{ID}, $1+1);
		} elsif ( $args->{steps}[0] =~ /n/i ) {
			sendTalkCancel($net, $args->{ID});
			$ai_v{'npc_talk'}{'time'} = time;
			$args->{time}	= time;
		} elsif ( $args->{steps}[0] =~ /^b(\d+),(\d+)/i ) {
			my $itemID = $storeList[$1]{nameID};
			$ai_v{npc_talk}{itemID} = $itemID;
			sendBuy($net, $itemID, $2);
		} elsif ( $args->{steps}[0] =~ /b/i ) {
			sendGetStoreList($net, $args->{ID});
		} elsif ( $args->{steps}[0] =~ /s/i ) {
			sendGetSellList($net, $args->{ID});
		} elsif ( $args->{steps}[0] =~ /e/i ) {
			$ai_v{npc_talk}{talk} = 'close';
		}
		shift @{$args->{steps}};
	}
}

##### PORTALRECORD #####
# Automatically record new unknown portals
sub processPortalRecording {
	return unless $config{portalRecord};
	return unless $ai_v{portalTrace_mapChanged} && timeOut($ai_v{portalTrace_mapChanged}, 0.5);
	delete $ai_v{portalTrace_mapChanged};

	debug "Checking for new portals...\n", "portalRecord";
	my $first = 1;
	my ($foundID, $smallDist, $dist);

	if (!$field{name}) {
		debug "Field name not known - abort\n", "portalRecord";
		return;
	}


	# Find the nearest portal or the only portal on the map
	# you came from (source portal)
	foreach (@portalsID_old) {
		next if (!$_);
		$dist = distance($char->{old_pos_to}, $portals_old{$_}{pos});
		if ($dist <= 7 && ($first || $dist < $smallDist)) {
			$smallDist = $dist;
			$foundID = $_;
			undef $first;
		}
	}

	my ($sourceMap, $sourceID, %sourcePos, $sourceIndex);
	if (defined $foundID) {
		$sourceMap = $portals_old{$foundID}{source}{map};
		$sourceID = $portals_old{$foundID}{nameID};
		%sourcePos = %{$portals_old{$foundID}{pos}};
		$sourceIndex = $foundID;
		debug "Source portal: $sourceMap ($sourcePos{x}, $sourcePos{y})\n", "portalRecord";
	} else {
		debug "No source portal found.\n", "portalRecord";
		return;
	}

	#if (defined portalExists($sourceMap, \%sourcePos)) {
	#	debug "Source portal is already in portals.txt - abort\n", "portalRecord";
	#	return;
	#}


	# Find the nearest portal or only portal on the
	# current map (destination portal)
	$first = 1;
	undef $foundID;
	undef $smallDist;

	foreach (@portalsID) {
		next if (!$_);
		$dist = distance($chars[$config{'char'}]{pos_to}, $portals{$_}{pos});
		if ($first || $dist < $smallDist) {
			$smallDist = $dist;
			$foundID = $_;
			undef $first;
		}
	}

	# Sanity checks
	if (!defined $foundID) {
		debug "No destination portal found.\n", "portalRecord";
		return;
	}
	#if (defined portalExists($field{name}, $portals{$foundID}{pos})) {
	#	debug "Destination portal is already in portals.txt\n", "portalRecord";
	#	last PORTALRECORD;
	#}
	if (defined portalExists2($sourceMap, \%sourcePos, $field{name}, $portals{$foundID}{pos})) {
		debug "This portal is already in portals.txt\n", "portalRecord";
		return;
	}


	# And finally, record the portal information
	my ($destMap, $destID, %destPos);
	$destMap = $field{name};
	$destID = $portals{$foundID}{nameID};
	%destPos = %{$portals{$foundID}{pos}};
	debug "Destination portal: $destMap ($destPos{x}, $destPos{y})\n", "portalRecord";

	$portals{$foundID}{name} = "$field{name} -> $sourceMap";
	$portals_old{$sourceIndex}{name} = "$sourceMap -> $field{name}";


	my ($ID, $destName);

	# Record information about destination portal
	if ($config{portalRecord} > 1 &&
	    !defined portalExists($field{name}, $portals{$foundID}{pos})) {
		$ID = "$field{name} $destPos{x} $destPos{y}";
		$portals_lut{$ID}{source}{map} = $field{name};
		$portals_lut{$ID}{source}{x} = $destPos{x};
		$portals_lut{$ID}{source}{y} = $destPos{y};
		$destName = "$sourceMap $sourcePos{x} $sourcePos{y}";
		$portals_lut{$ID}{dest}{$destName}{map} = $sourceMap;
		$portals_lut{$ID}{dest}{$destName}{x} = $sourcePos{x};
		$portals_lut{$ID}{dest}{$destName}{y} = $sourcePos{y};

		message TF("Recorded new portal (destination): %s (%s, %s) -> %s (%s, %s)\n", $field{name}, $destPos{x}, $destPos{y}, $sourceMap, $sourcePos{x}, $sourcePos{y}), "portalRecord";
		updatePortalLUT("$Settings::tables_folder/portals.txt",
				$field{name}, $destPos{x}, $destPos{y},
				$sourceMap, $sourcePos{x}, $sourcePos{y});
	}

	# Record information about the source portal
	if (!defined portalExists($sourceMap, \%sourcePos)) {
		$ID = "$sourceMap $sourcePos{x} $sourcePos{y}";
		$portals_lut{$ID}{source}{map} = $sourceMap;
		$portals_lut{$ID}{source}{x} = $sourcePos{x};
		$portals_lut{$ID}{source}{y} = $sourcePos{y};
		$destName = "$field{name} $destPos{x} $destPos{y}";
		$portals_lut{$ID}{dest}{$destName}{map} = $field{name};
		$portals_lut{$ID}{dest}{$destName}{x} = $destPos{x};
		$portals_lut{$ID}{dest}{$destName}{y} = $destPos{y};

		message TF("Recorded new portal (source): %s (%s, %s) -> %s (%s, %s)\n", $sourceMap, $sourcePos{x}, $sourcePos{y}, $field{name}, $char->{pos}{x}, $char->{pos}{y}), "portalRecord";
		updatePortalLUT("$Settings::tables_folder/portals.txt",
				$sourceMap, $sourcePos{x}, $sourcePos{y},
				$field{name}, $char->{pos}{x}, $char->{pos}{y});
	}
}

##### SITTING #####
sub processSit {
	if (AI::action eq "sitting") {
		if ($char->{sitting} || $char->{skills}{NV_BASIC}{lv} < 3) {
			# Stop if we're already sitting
			AI::dequeue;
			$timeout{ai_sit}{time} = $timeout{ai_sit_wait}{time} = 0;

		} elsif (!$char->{sitting} && timeOut($timeout{ai_sit}) && timeOut($timeout{ai_sit_wait})) {
			# Send the 'sit' packet every x seconds until we're sitting
			sendSit($net);
			$timeout{ai_sit}{time} = time;

			look($config{sitAuto_look}) if (defined $config{sitAuto_look});
		}
	}
}

##### STANDING #####
sub processStand {
	# Same logic as the 'sitting' AI
	if (AI::action eq "standing") {
		if (!$char->{sitting}) {
			AI::dequeue;

		} elsif (timeOut($timeout{ai_sit}) && timeOut($timeout{ai_stand_wait})) {
			sendStand($net);
			$timeout{ai_sit}{time} = time;
		}
	}
}

##### ATTACK #####
sub processAttack {
	Benchmark::begin("ai_attack") if DEBUG;

	if (AI::action eq "attack" && AI::args->{suspended}) {
		AI::args->{ai_attack_giveup}{time} += time - AI::args->{suspended};
		delete AI::args->{suspended};
	}

	if (AI::action eq "attack" && AI::args->{move_start}) {
		# We've just finished moving to the monster.
		# Don't count the time we spent on moving
		AI::args->{ai_attack_giveup}{time} += time - AI::args->{move_start};
		undef AI::args->{unstuck}{time};
		undef AI::args->{move_start};

	} elsif (AI::action eq "attack" && AI::args->{avoiding} && AI::args->{attackID}) {
		my $target = Actor::get(AI::args->{attackID});
		AI::args->{ai_attack_giveup}{time} = time + $target->{time_move_calc} + 3;
		undef AI::args->{avoiding};

	} elsif (((AI::action eq "route" && AI::action(1) eq "attack") || (AI::action eq "move" && AI::action(2) eq "attack"))
	   && AI::args->{attackID} && timeOut($AI::Temp::attack_route_adjust, 1)) {
		# We're on route to the monster; check whether the monster has moved
		my $ID = AI::args->{attackID};
		my $attackSeq = (AI::action eq "route") ? AI::args(1) : AI::args(2);
		my $target = Actor::get($ID);

		if ($target->{type} ne 'Unknown' && $attackSeq->{monsterPos} && %{$attackSeq->{monsterPos}}
		 && distance(calcPosition($target), $attackSeq->{monsterPos}) > $attackSeq->{attackMethod}{maxDistance}) {
			# Monster has moved; stop moving and let the attack AI readjust route
			AI::dequeue;
			AI::dequeue if (AI::action eq "route");

			$attackSeq->{ai_attack_giveup}{time} = time;
			debug "Target has moved more than $attackSeq->{attackMethod}{maxDistance} blocks; readjusting route\n", "ai_attack";

		} elsif ($target->{type} ne 'Unknown' && $attackSeq->{monsterPos} && %{$attackSeq->{monsterPos}}
		 && distance(calcPosition($target), calcPosition($char)) <= $attackSeq->{attackMethod}{maxDistance}) {
			# Monster is within attack range; stop moving
			AI::dequeue;
			AI::dequeue if (AI::action eq "route");

			$attackSeq->{ai_attack_giveup}{time} = time;
			debug "Target at ($attackSeq->{monsterPos}{x},$attackSeq->{monsterPos}{y}) is now within " .
				"$attackSeq->{attackMethod}{maxDistance} blocks; stop moving\n", "ai_attack";
		}
		$AI::Temp::attack_route_adjust = time;
	}

	if (AI::action eq "attack" &&
	    (timeOut(AI::args->{ai_attack_giveup}) ||
		 AI::args->{unstuck}{count} > 5) &&
		!$config{attackNoGiveup}) {
		my $ID = AI::args->{ID};
		my $target = Actor::get($ID);
		$target->{attack_failed} = time if ($monsters{$ID});
		AI::dequeue;
		message T("Can't reach or damage target, dropping target\n"), "ai_attack";
		if ($config{'teleportAuto_dropTarget'}) {
			message T("Teleport due to dropping attack target\n");
			useTeleport(1);
		}

	} elsif (AI::action eq "attack" && !$monsters{AI::args->{ID}} && (!$players{AI::args->{ID}} || $players{AI::args->{ID}}{dead})) {
		# Monster died or disappeared
		$timeout{'ai_attack'}{'time'} -= $timeout{'ai_attack'}{'timeout'};
		my $ID = AI::args->{ID};
		AI::dequeue;

		if ($monsters_old{$ID} && $monsters_old{$ID}{dead}) {
			message T("Target died\n"), "ai_attack";
			monKilled();

			# Pickup loot when monster's dead
			if ($AI == 2 && $config{'itemsTakeAuto'} && $monsters_old{$ID}{dmgFromYou} > 0 && !$monsters_old{$ID}{ignore}) {
				AI::clear("items_take");
				ai_items_take($monsters_old{$ID}{pos}{x}, $monsters_old{$ID}{pos}{y},
					$monsters_old{$ID}{pos_to}{x}, $monsters_old{$ID}{pos_to}{y});
			} else {
				# Cheap way to suspend all movement to make it look real
				ai_clientSuspend(0, $timeout{'ai_attack_waitAfterKill'}{'timeout'});
			}

			## kokal start
			## mosters counting
			my $i = 0;
			my $found = 0;
			while ($monsters_Killed[$i]) {
				if ($monsters_Killed[$i]{'nameID'} eq $monsters_old{$ID}{'nameID'}) {
					$monsters_Killed[$i]{'count'}++;
					monsterLog($monsters_Killed[$i]{'name'});
					$found = 1;
					last;
				}
				$i++;
			}
			if (!$found) {
				$monsters_Killed[$i]{'nameID'} = $monsters_old{$ID}{'nameID'};
				$monsters_Killed[$i]{'name'} = $monsters_old{$ID}{'name'};
				$monsters_Killed[$i]{'count'} = 1;
				monsterLog($monsters_Killed[$i]{'name'})
			}
			## kokal end

		} else {
			message T("Target lost\n"), "ai_attack";
		}

	} elsif (AI::action eq "attack") {
		# The attack sequence hasn't timed out and the monster is on screen

		# Update information about the monster and the current situation
		my $args = AI::args;
		my $followIndex = AI::findAction("follow");
		my $following;
		my $followID;
		if (defined $followIndex) {
			$following = AI::args($followIndex)->{following};
			$followID = AI::args($followIndex)->{ID};
		}

		my $ID = $args->{ID};
		my $target = Actor::get($ID);
		my $myPos = $char->{pos_to};
		my $monsterPos = $target->{pos_to};
		my $monsterDist = distance($myPos, $monsterPos);

		my ($realMyPos, $realMonsterPos, $realMonsterDist, $hitYou);
		my $realMyPos = calcPosition($char);
		my $realMonsterPos = calcPosition($target);
		my $realMonsterDist = distance($realMyPos, $realMonsterPos);
		if (!$config{'runFromTarget'}) {
			$myPos = $realMyPos;
			$monsterPos = $realMonsterPos;
		}

		my $cleanMonster = checkMonsterCleanness($ID);


		# If the damage numbers have changed, update the giveup time so we don't timeout
		if ($args->{dmgToYou_last}   != $target->{dmgToYou}
		 || $args->{missedYou_last}  != $target->{missedYou}
		 || $args->{dmgFromYou_last} != $target->{dmgFromYou}
		 || $args->{lastSkillTime} != $char->{last_skill_time}) {
			$args->{ai_attack_giveup}{time} = time;
			debug "Update attack giveup time\n", "ai_attack", 2;
		}
		$hitYou = ($args->{dmgToYou_last} != $target->{dmgToYou}
			|| $args->{missedYou_last} != $target->{missedYou});
		$args->{dmgToYou_last} = $target->{dmgToYou};
		$args->{missedYou_last} = $target->{missedYou};
		$args->{dmgFromYou_last} = $target->{dmgFromYou};
		$args->{missedFromYou_last} = $target->{missedFromYou};
		$args->{lastSkillTime} = $char->{last_skill_time};


		# Determine what combo skill to use
		delete $args->{attackMethod};
		my $lastSkill = Skills->new(id => $char->{last_skill_used})->name;
		my $i = 0;
		while (exists $config{"attackComboSlot_$i"}) {
			if (!$config{"attackComboSlot_$i"}) {
				$i++;
				next;
			}

			if ($config{"attackComboSlot_${i}_afterSkill"} eq $lastSkill
			 && ( !$config{"attackComboSlot_${i}_maxUses"} || $args->{attackComboSlot_uses}{$i} < $config{"attackComboSlot_${i}_maxUses"} )
			 && ( !$config{"attackComboSlot_${i}_autoCombo"} || ($char->{combo_packet} && $config{"attackComboSlot_${i}_autoCombo"}) )
			 && ( !defined($args->{ID}) || $args->{ID} eq $char->{last_skill_target} || !$config{"attackComboSlot_${i}_isSelfSkill"})
			 && checkSelfCondition("attackComboSlot_$i")
			 && (!$config{"attackComboSlot_${i}_monsters"} || existsInList($config{"attackComboSlot_${i}_monsters"}, $target->{name}))
			 && (!$config{"attackComboSlot_${i}_notMonsters"} || !existsInList($config{"attackComboSlot_${i}_notMonsters"}, $target->{name}))
			 && checkMonsterCondition("attackComboSlot_${i}_target", $target)) {

				$args->{attackComboSlot_uses}{$i}++;
				delete $char->{last_skill_used};
				if ($config{"attackComboSlot_${i}_autoCombo"}) {
					$char->{combo_packet} = 1500 if ($char->{combo_packet} > 1500);
					# eAthena seems to have a bug where the combo_packet overflows and gives an
					# abnormally high number. This causes kore to get stuck in a waitBeforeUse timeout.
					$config{"attackComboSlot_${i}_waitBeforeUse"} = ($char->{combo_packet} / 1000);
				}
				delete $char->{combo_packet};
				$args->{attackMethod}{type} = "combo";
				$args->{attackMethod}{comboSlot} = $i;
				$args->{attackMethod}{distance} = $config{"attackComboSlot_${i}_dist"};
				$args->{attackMethod}{maxDistance} = $config{"attackComboSlot_${i}_dist"};
				$args->{attackMethod}{isSelfSkill} = $config{"attackComboSlot_${i}_isSelfSkill"};
				last;
			}
			$i++;
		}

		# Determine what skill to use to attack
		if (!$args->{attackMethod}{type}) {
			if ($config{'attackUseWeapon'}) {
				$args->{attackMethod}{distance} = $config{'attackDistance'};
				$args->{attackMethod}{maxDistance} = $config{'attackMaxDistance'};
				$args->{attackMethod}{type} = "weapon";
			} else {
				$args->{attackMethod}{distance} = 30;
				$args->{attackMethod}{maxDistance} = 30;
				undef $args->{attackMethod}{type};
			}

			$i = 0;
			while (exists $config{"attackSkillSlot_$i"}) {
				if (!$config{"attackSkillSlot_$i"}) {
					$i++;
					next;
				}

				my $skill = Skills->new(name => $config{"attackSkillSlot_$i"});
				if (checkSelfCondition("attackSkillSlot_$i")
					&& (!$config{"attackSkillSlot_$i"."_maxUses"} ||
					    $target->{skillUses}{$skill->handle} < $config{"attackSkillSlot_$i"."_maxUses"})
					&& (!$config{"attackSkillSlot_$i"."_maxAttempts"} || $args->{attackSkillSlot_attempts}{$i} < $config{"attackSkillSlot_$i"."_maxAttempts"})
					&& (!$config{"attackSkillSlot_$i"."_monsters"} || existsInList($config{"attackSkillSlot_$i"."_monsters"}, $target->{'name'}))
					&& (!$config{"attackSkillSlot_$i"."_notMonsters"} || !existsInList($config{"attackSkillSlot_$i"."_notMonsters"}, $target->{'name'}))
					&& (!$config{"attackSkillSlot_$i"."_previousDamage"} || inRange($target->{dmgTo}, $config{"attackSkillSlot_$i"."_previousDamage"}))
					&& checkMonsterCondition("attackSkillSlot_${i}_target", $target)
				) {
					$args->{attackSkillSlot_attempts}{$i}++;
					$args->{attackMethod}{distance} = $config{"attackSkillSlot_$i"."_dist"};
					$args->{attackMethod}{maxDistance} = $config{"attackSkillSlot_$i"."_dist"};
					$args->{attackMethod}{type} = "skill";
					$args->{attackMethod}{skillSlot} = $i;
					last;
				}
				$i++;
			}

			if ($config{'runFromTarget'} && $config{'runFromTarget_dist'} > $args->{attackMethod}{distance}) {
				$args->{attackMethod}{distance} = $config{'runFromTarget_dist'};
			}
		}

		$args->{attackMethod}{maxDistance} ||= $config{attackMaxDistance};
		$args->{attackMethod}{distance} ||= $config{attackDistance};
		if ($args->{attackMethod}{maxDistance} < $args->{attackMethod}{distance}) {
			$args->{attackMethod}{maxDistance} = $args->{attackMethod}{distance};
		}

		if ($char->{sitting}) {
			ai_setSuspend(0);
			stand();

		} elsif (!$cleanMonster) {
			# Drop target if it's already attacked by someone else
			message T("Dropping target - you will not kill steal others\n"), "ai_attack";
			sendMove($realMyPos->{x}, $realMyPos->{y});
			AI::dequeue;
			if ($config{teleportAuto_dropTargetKS}) {
				message T("Teleporting due to dropping attack target\n"), "teleport";
				useTeleport(1);
			}

		} elsif ($config{attackCheckLOS} &&
			 $args->{attackMethod}{distance} > 2 &&
			 !checkLineSnipable($realMyPos, $realMonsterPos)) {
			# We are a ranged attacker without LOS

			# Calculate squares around monster within shooting range, but not
			# closer than runFromTarget_dist
			my @stand = calcRectArea2($realMonsterPos->{x}, $realMonsterPos->{y},
						  $args->{attackMethod}{distance},
									  $config{runFromTarget} ? $config{runFromTarget_dist} : 0);

			my ($master, $masterPos);
			if ($config{follow}) {
				foreach (keys %players) {
					if ($players{$_}{name} eq $config{followTarget}) {
						$master = $players{$_};
						last;
					}
				}
				$masterPos = calcPosition($master) if $master;
			}

			# Determine which of these spots are snipable
			my $best_spot;
			my $best_dist;
			for my $spot (@stand) {
				# Is this spot acceptable?
				# 1. It must have LOS to the target ($realMonsterPos).
				# 2. It must be within $config{followDistanceMax} of
				#    $masterPos, if we have a master.
				if (checkLineSnipable($spot, $realMonsterPos) &&
				    (!$master || distance($spot, $masterPos) <= $config{followDistanceMax})) {
					# FIXME: use route distance, not pythagorean distance
					my $dist = distance($realMyPos, $spot);
					if (!defined($best_dist) || $dist < $best_dist) {
						$best_dist = $dist;
						$best_spot = $spot;
					}
				}
			}

			# Move to the closest spot
			my $msg = "No LOS from ($realMyPos->{x}, $realMyPos->{y}) to target ($realMonsterPos->{x}, $realMonsterPos->{y})";
			if ($best_spot) {
				message TF("%s; moving to (%s, %s)\n", $msg, $best_spot->{x}, $best_spot->{y});
				ai_route($field{name}, $best_spot->{x}, $best_spot->{y});
			} else {
				warning TF("%s; no acceptable place to stand\n", $msg);
				AI::dequeue;
			}

		} elsif ($config{'runFromTarget'} && ($monsterDist < $config{'runFromTarget_dist'} || $hitYou)) {
			#my $begin = time;
			# Get a list of blocks that we can run to
			my @blocks = calcRectArea($myPos->{x}, $myPos->{y},
				# If the monster hit you while you're running, then your recorded
				# location may be out of date. So we use a smaller distance so we can still move.
				($hitYou) ? $config{'runFromTarget_dist'} / 2 : $config{'runFromTarget_dist'});

			# Find the distance value of the block that's farthest away from a wall
			my $highest;
			foreach (@blocks) {
				my $dist = ord(substr($field{dstMap}, $_->{y} * $field{width} + $_->{x}));
				if (!defined $highest || $dist > $highest) {
					$highest = $dist;
				}
			}

			# Get rid of rediculously large route distances (such as spots that are on a hill)
			# Get rid of blocks that are near a wall
			my $pathfinding = new PathFinding;
			use constant AVOID_WALLS => 4;
			for (my $i = 0; $i < @blocks; $i++) {
				# We want to avoid walls (so we don't get cornered), if possible
				my $dist = ord(substr($field{dstMap}, $blocks[$i]{y} * $field{width} + $blocks[$i]{x}));
				if ($highest >= AVOID_WALLS && $dist < AVOID_WALLS) {
					delete $blocks[$i];
					next;
				}

				$pathfinding->reset(
					field => \%field,
					start => $myPos,
					dest => $blocks[$i]);
				my $ret = $pathfinding->runcount;
				if ($ret <= 0 || $ret > $config{'runFromTarget_dist'} * 2) {
					delete $blocks[$i];
					next;
				}
			}

			# Find the block that's farthest to us
			my $largestDist;
			my $bestBlock;
			foreach (@blocks) {
				next unless defined $_;
				my $dist = distance($monsterPos, $_);
				if (!defined $largestDist || $dist > $largestDist) {
					$largestDist = $dist;
					$bestBlock = $_;
				}
			}

			#message "Time spent: " . (time - $begin) . "\n";
			#debug_showSpots('runFromTarget', \@blocks, $bestBlock);
			AI::args->{avoiding} = 1;
			move($bestBlock->{x}, $bestBlock->{y}, $ID);

		} elsif (!$config{'runFromTarget'} && $monsterDist > $args->{attackMethod}{maxDistance}
		  && timeOut($args->{ai_attack_giveup}, 0.5)) {
			# The target monster moved; move to target
			$args->{move_start} = time;
			$args->{monsterPos} = {%{$monsterPos}};

			# Calculate how long it would take to reach the monster.
			# Calculate where the monster would be when you've reached its
			# previous position.
			my $time_needed;
			if (objectIsMovingTowards($target, $char, 45)) {
				$time_needed = $monsterDist * $char->{walk_speed};
			} else {
				# If monster is not moving towards you, then you need more time to walk
				$time_needed = $monsterDist * $char->{walk_speed} + 2;
			}
			my $pos = calcPosition($target, $time_needed);

			my $dist = sprintf("%.1f", $monsterDist);
			debug "Target distance $dist is >$args->{attackMethod}{maxDistance}; moving to target: " .
				"from ($myPos->{x},$myPos->{y}) to ($pos->{x},$pos->{y})\n", "ai_attack";

			my $result = ai_route($field{'name'}, $pos->{x}, $pos->{y},
				distFromGoal => $args->{attackMethod}{distance},
				maxRouteTime => $config{'attackMaxRouteTime'},
				attackID => $ID,
				noMapRoute => 1,
				noAvoidWalls => 1);
			if (!$result) {
				# Unable to calculate a route to target
				$target->{attack_failed} = time;
				AI::dequeue;
 				message T("Unable to calculate a route to target, dropping target\n"), "ai_attack";
				if ($config{'teleportAuto_dropTarget'}) {
					message T("Teleport due to dropping attack target\n");
					useTeleport(1);
				}
			}

		} elsif ((!$config{'runFromTarget'} || $realMonsterDist >= $config{'runFromTarget_dist'})
		 && (!$config{'tankMode'} || !$target->{dmgFromYou})) {
			# Attack the target. In case of tanking, only attack if it hasn't been hit once.
			if (!AI::args->{firstAttack}) {
				AI::args->{firstAttack} = 1;
				my $dist = sprintf("%.1f", $monsterDist);
				my $pos = "$myPos->{x},$myPos->{y}";
				debug "Ready to attack target (which is $dist blocks away); we're at ($pos)\n", "ai_attack";
			}

			$args->{unstuck}{time} = time if (!$args->{unstuck}{time});
			if (!$target->{dmgFromYou} && timeOut($args->{unstuck})) {
				# We are close enough to the target, and we're trying to attack it,
				# but some time has passed and we still haven't dealed any damage.
				# Our recorded position might be out of sync, so try to unstuck
				$args->{unstuck}{time} = time;
				debug("Attack - trying to unstuck\n", "ai_attack");
				move($myPos->{x}, $myPos->{y});
				$args->{unstuck}{count}++;
			}

			if ($args->{attackMethod}{type} eq "weapon" && timeOut($timeout{ai_attack})) {
				if (Item::scanConfigAndCheck("attackEquip")) {
					#check if item needs to be equipped
					Item::scanConfigAndEquip("attackEquip");
				} else {
					sendAttack($net, $ID,
						($config{'tankMode'}) ? 0 : 7);
					$timeout{ai_attack}{time} = time;
					delete $args->{attackMethod};
				}
			} elsif ($args->{attackMethod}{type} eq "skill") {
				my $slot = $args->{attackMethod}{skillSlot};
				delete $args->{attackMethod};

				ai_setSuspend(0);
				my $skill = Skills->new(name => lc($config{"attackSkillSlot_$slot"}));
				if (!ai_getSkillUseType($skill->handle)) {
					ai_skillUse(
						$skill->handle,
						$config{"attackSkillSlot_${slot}_lvl"},
						$config{"attackSkillSlot_${slot}_maxCastTime"},
						$config{"attackSkillSlot_${slot}_minCastTime"},
						$config{"attackSkillSlot_${slot}_isSelfSkill"} ? $accountID : $ID,
						undef,
						"attackSkill",
						undef,
						undef,
						"attackSkillSlot_${slot}");
				} else {
					my $pos = calcPosition($config{"attackSkillSlot_${slot}_isSelfSkill"} ? $char : $target);
					ai_skillUse(
						$skill->handle,
						$config{"attackSkillSlot_${slot}_lvl"},
						$config{"attackSkillSlot_${slot}_maxCastTime"},
						$config{"attackSkillSlot_${slot}_minCastTime"},
						$pos->{x},
						$pos->{y},
						"attackSkill",
						undef,
						undef,
						"attackSkillSlot_${slot}");
				}
				$args->{monsterID} = $ID;

				debug "Auto-skill on monster ".getActorName($ID).": ".qq~$config{"attackSkillSlot_$slot"} (lvl $config{"attackSkillSlot_${slot}_lvl"})\n~, "ai_attack";

			} elsif ($args->{attackMethod}{type} eq "combo") {
				my $slot = $args->{attackMethod}{comboSlot};
				my $isSelfSkill = $args->{attackMethod}{isSelfSkill};
				my $skill = Skills->new(name => $config{"attackComboSlot_$slot"})->handle;
				delete $args->{attackMethod};

				if (!ai_getSkillUseType($skill)) {
					my $targetID = ($isSelfSkill) ? $accountID : $ID;
					ai_skillUse(
						$skill,
						$config{"attackComboSlot_${slot}_lvl"},
						$config{"attackComboSlot_${slot}_maxCastTime"},
						$config{"attackComboSlot_${slot}_minCastTime"},
						$targetID,
						undef,
						undef,
						undef,
						$config{"attackComboSlot_${slot}_waitBeforeUse"});
				} else {
					my $pos = ($isSelfSkill) ? $char->{pos_to} : $target->{pos_to};
					ai_skillUse(
						$skill,
						$config{"attackComboSlot_${slot}_lvl"},
						$config{"attackComboSlot_${slot}_maxCastTime"},
						$config{"attackComboSlot_${slot}_minCastTime"},
						$pos->{x},
						$pos->{y},
						undef,
						undef,
						$config{"attackComboSlot_${slot}_waitBeforeUse"});
				}
				$args->{monsterID} = $ID;
			}

		} elsif ($config{'tankMode'}) {
			if ($args->{'dmgTo_last'} != $target->{'dmgTo'}) {
				$args->{'ai_attack_giveup'}{'time'} = time;
			}
			$args->{'dmgTo_last'} = $target->{'dmgTo'};
		}
	}

	# Check for kill steal while moving
	if (AI::is("move", "route") && AI::args->{attackID} && AI::inQueue("attack")) {
		my $ID = AI::args->{attackID};
		if ($monsters{$ID} && !checkMonsterCleanness($ID)) {
			message T("Dropping target - you will not kill steal others\n");
			stopAttack();
			$monsters{$ID}{ignore} = 1;

			# Right now, the queue is either
			#   move, route, attack
			# -or-
			#   route, attack
			AI::dequeue;
			AI::dequeue;
			AI::dequeue if (AI::action eq "attack");
			if ($config{teleportAuto_dropTargetKS}) {
				message T("Teleport due to dropping attack target\n");
				useTeleport(1);
			}
		}
	}

	Benchmark::end("ai_attack") if DEBUG;
}

##### SKILL USE #####
sub processSkillUse {
	#FIXME: need to move closer before using skill on player,
	#there might be line of sight problem too
	#or the player disappers from the area

	if (AI::action eq "skill_use" && AI::args->{suspended}) {
		AI::args->{giveup}{time} += time - AI::args->{suspended};
		AI::args->{minCastTime}{time} += time - AI::args->{suspended};
		AI::args->{maxCastTime}{time} += time - AI::args->{suspended};
		delete AI::args->{suspended};
	}

	SKILL_USE: {
		last SKILL_USE if (AI::action ne "skill_use");
		my $args = AI::args;

		if ($args->{monsterID} && $skillsArea{$args->{skillHandle}} == 2) {
			delete $args->{monsterID};
		}

		if (exists $args->{ai_equipAuto_skilluse_giveup} && binFind(\@skillsID, $args->{skillHandle}) eq "" && timeOut($args->{ai_equipAuto_skilluse_giveup})) {
			warning T("Timeout equiping for skill\n");
			AI::dequeue;
			${$args->{ret}} = 'equip timeout' if ($args->{ret});
		} elsif (Item::scanConfigAndCheck("$args->{prefix}_equip")) {
			#check if item needs to be equipped
			Item::scanConfigAndEquip("$args->{prefix}_equip");
		} elsif (timeOut($args->{waitBeforeUse})) {
			if (defined $args->{monsterID} && !defined $monsters{$args->{monsterID}}) {
				# This skill is supposed to be used for attacking a monster, but that monster has died
				AI::dequeue;
				${$args->{ret}} = 'target gone' if ($args->{ret});

			} elsif ($char->{sitting}) {
				AI::suspend;
				stand();

			# Use skill if we haven't done so yet
			} elsif (!$args->{skill_used}) {
				my $handle = $args->{skillHandle};
				if (!defined $args->{skillID}) {
					my $skill = new Skills(handle => $handle);
					$args->{skillID} = $skill->id;
				}
				my $skillID = $args->{skillID};

				if ($handle eq 'AL_TELEPORT') {
					${$args->{ret}} = 'ok' if ($args->{ret});
					AI::dequeue;
					useTeleport($args->{lv});
					last SKILL_USE;
				}

				$args->{skill_used} = 1;
				$args->{giveup}{time} = time;

				# Stop attacking, otherwise skill use might fail
				my $attackIndex = AI::findAction("attack");
				if (defined($attackIndex) && AI::args($attackIndex)->{attackMethod}{type} eq "weapon") {
					# 2005-01-24 pmak: Commenting this out since it may
					# be causing bot to attack slowly when a buff runs
					# out.
					#stopAttack();
				}

				# Give an error if we don't actually possess this skill
				my $skill = new Skills(handle => $handle);
				if ($char->{skills}{$handle}{lv} <= 0 && (!$char->{permitSkill} || $char->{permitSkill}->handle ne $handle)) {
					debug "Attempted to use skill (".$skill->name.") which you do not have.\n";
				}

				$args->{maxCastTime}{time} = time;
				if ($skillsArea{$handle} == 2) {
					sendSkillUse($net, $skillID, $args->{lv}, $accountID);
				} elsif ($args->{x} ne "") {
					sendSkillUseLoc($net, $skillID, $args->{lv}, $args->{x}, $args->{y});
				} else {
					sendSkillUse($net, $skillID, $args->{lv}, $args->{target});
				}
				undef $char->{permitSkill};
				$args->{skill_use_last} = $char->{skills}{$handle}{time_used};

				delete $char->{cast_cancelled};

			} elsif (timeOut($args->{minCastTime})) {
				if ($args->{skill_use_last} != $char->{skills}{$args->{skillHandle}}{time_used}) {
					AI::dequeue;
					${$args->{ret}} = 'ok' if ($args->{ret});

				} elsif ($char->{cast_cancelled} > $char->{time_cast}) {
					AI::dequeue;
					${$args->{ret}} = 'cancelled' if ($args->{ret});

				} elsif (timeOut($char->{time_cast}, $char->{time_cast_wait} + 0.5)
				  && ( (timeOut($args->{giveup}) && (!$char->{time_cast} || !$args->{maxCastTime}{timeout}) )
				      || ( $args->{maxCastTime}{timeout} && timeOut($args->{maxCastTime})) )
				) {
					AI::dequeue;
					${$args->{ret}} = 'timeout' if ($args->{ret});
				}
			}
		}
	}
}

####### ROUTE #######
sub processRouteAI {
	if (AI::action eq "route" && AI::args->{suspended}) {
		AI::args->{time_start} += time - AI::args->{suspended};
		AI::args->{time_step} += time - AI::args->{suspended};
		delete AI::args->{suspended};
	}

	if (AI::action eq "route" && $field{'name'} && $char->{pos_to}{x} ne '' && $char->{pos_to}{y} ne '') {
		my $args = AI::args;

		if ( $args->{maxRouteTime} && timeOut($args->{time_start}, $args->{maxRouteTime})) {
			# We spent too much time
			debug "Route - we spent too much time; bailing out.\n", "route";
			AI::dequeue;

		} elsif ($field{name} ne $args->{dest}{map} || $args->{mapChanged}) {
			debug "Map changed: $field{name} $args->{dest}{map}\n", "route";
			AI::dequeue;

		} elsif ($args->{stage} eq '') {
			my $pos = calcPosition($char);
			$args->{solution} = [];
			if (ai_route_getRoute($args->{solution}, \%field, $pos, $args->{dest}{pos})) {
				$args->{stage} = 'Route Solution Ready';
				debug "Route Solution Ready\n", "route";
			} else {
				debug "Something's wrong; there is no path to $field{name}($args->{dest}{pos}{x},$args->{dest}{pos}{y}).\n", "debug";
				AI::dequeue;
			}

		} elsif ($args->{stage} eq 'Route Solution Ready') {
			my $solution = $args->{solution};
			if ($args->{maxRouteDistance} > 0 && $args->{maxRouteDistance} < 1) {
				# Fractional route motion
				$args->{maxRouteDistance} = int($args->{maxRouteDistance} * scalar(@{$solution}));
			}
			splice(@{$solution}, 1 + $args->{maxRouteDistance}) if $args->{maxRouteDistance} && $args->{maxRouteDistance} < @{$solution};

			# Trim down solution tree for pyDistFromGoal or distFromGoal
			if ($args->{pyDistFromGoal}) {
				my $trimsteps = 0;
				$trimsteps++ while ($trimsteps < @{$solution}
						 && distance($solution->[@{$solution} - 1 - $trimsteps], $solution->[@{$solution} - 1]) < $args->{pyDistFromGoal}
					);
				debug "Route - trimming down solution by $trimsteps steps for pyDistFromGoal $args->{'pyDistFromGoal'}\n", "route";
				splice(@{$args->{'solution'}}, -$trimsteps) if ($trimsteps);
			} elsif ($args->{distFromGoal}) {
				my $trimsteps = $args->{distFromGoal};
				$trimsteps = @{$args->{'solution'}} if $trimsteps > @{$args->{'solution'}};
				debug "Route - trimming down solution by $trimsteps steps for distFromGoal $args->{'distFromGoal'}\n", "route";
				splice(@{$args->{solution}}, -$trimsteps) if ($trimsteps);
			}

			undef $args->{mapChanged};
			undef $args->{index};
			undef $args->{old_x};
			undef $args->{old_y};
			undef $args->{new_x};
			undef $args->{new_y};
			$args->{time_step} = time;
			$args->{stage} = 'Walk the Route Solution';

		} elsif ($args->{stage} eq 'Walk the Route Solution') {

			my $pos = calcPosition($char);
			my ($cur_x, $cur_y) = ($pos->{x}, $pos->{y});

			unless (@{$args->{solution}}) {
				# No more points to cover; we've arrived at the destination
				if ($args->{notifyUponArrival}) {
 					message T("Destination reached.\n"), "success";
				} else {
					debug "Destination reached.\n", "route";
				}
				AI::dequeue;

			} elsif ($args->{old_x} == $cur_x && $args->{old_y} == $cur_y && timeOut($args->{time_step}, 3)) {
				# We tried to move for 3 seconds, but we are still on the same spot,
				# decrease step size.
				# However, if $args->{index} was already 0, then that means
				# we were almost at the destination (only 1 more step is needed).
				# But we got interrupted (by auto-attack for example). Don't count that
				# as stuck.
				my $wasZero = $args->{index} == 0;
				$args->{index} = int($args->{index} * 0.8);
				if ($args->{index}) {
					debug "Route - not moving, decreasing step size to $args->{index}\n", "route";
					if (@{$args->{solution}}) {
						# If we still have more points to cover, walk to next point
						$args->{index} = @{$args->{solution}} - 1 if $args->{index} >= @{$args->{solution}};
						$args->{new_x} = $args->{solution}[$args->{index}]{x};
						$args->{new_y} = $args->{solution}[$args->{index}]{y};
						$args->{time_step} = time;
						move($args->{new_x}, $args->{new_y}, $args->{attackID});
					}
				} elsif (!$wasZero) {
					# We're stuck
					my $msg = TF("Stuck at %s (%d,%d), while walking from (%d,%d) to (%d,%d).", 
						$field{name}, $char->{pos_to}{x}, $char->{pos_to}{y}, $cur_x, $cur_y, $args->{dest}{pos}{x}, $args->{dest}{pos}{y});
					$msg .= T(" Teleporting to unstuck.") if $config{teleportAuto_unstuck};
					$msg .= "\n";
					warning $msg, "route";
					useTeleport(1) if $config{teleportAuto_unstuck};
					AI::dequeue;
				} else {
					$args->{time_step} = time;
				}

			} else {
				# We're either starting to move or already moving, so send out more
				# move commands periodically to keep moving and updating our position
				my $solution = $args->{solution};
				$args->{index} = $config{'route_step'} unless $args->{index};
				$args->{index}++ if ($args->{index} < $config{'route_step'});

				if (defined($args->{old_x}) && defined($args->{old_y})) {
					# See how far we've walked since the last move command and
					# trim down the soultion tree by this distance.
					# Only remove the last step if we reached the destination
					my $trimsteps = 0;
					# If position has changed, we must have walked at least one step
					$trimsteps++ if ($cur_x != $args->{'old_x'} || $cur_y != $args->{'old_y'});
					# Search the best matching entry for our position in the solution
					while ($trimsteps < @{$solution}
							 && distance( { x => $cur_x, y => $cur_y }, $solution->[$trimsteps + 1])
							    < distance( { x => $cur_x, y => $cur_y }, $solution->[$trimsteps])
						) {
						$trimsteps++;
					}
					# Remove the last step also if we reached the destination
					$trimsteps = @{$solution} - 1 if ($trimsteps >= @{$solution});
					#$trimsteps = @{$solution} if ($trimsteps <= $args->{'index'} && $args->{'new_x'} == $cur_x && $args->{'new_y'} == $cur_y);
					$trimsteps = @{$solution} if ($cur_x == $solution->[$#{$solution}]{x} && $cur_y == $solution->[$#{$solution}]{y});
					debug "Route - trimming down solution (" . @{$solution} . ") by $trimsteps steps\n", "route";
					splice(@{$solution}, 0, $trimsteps) if ($trimsteps > 0);
				}

				my $stepsleft = @{$solution};
				if ($stepsleft > 0) {
					# If we still have more points to cover, walk to next point
					$args->{index} = $stepsleft - 1 if ($args->{index} >= $stepsleft);
					$args->{new_x} = $args->{solution}[$args->{index}]{x};
					$args->{new_y} = $args->{solution}[$args->{index}]{y};

					# But first, check whether the distance of the next point isn't abnormally large.
					# If it is, then we've moved to an unexpected place. This could be caused by auto-attack,
					# for example.
					my %nextPos = (x => $args->{new_x}, y => $args->{new_y});
					if (distance(\%nextPos, $pos) > $config{'route_step'}) {
						debug "Route - movement interrupted: reset route\n", "route";
						$args->{stage} = '';

					} else {
						$args->{old_x} = $cur_x;
						$args->{old_y} = $cur_y;
						$args->{time_step} = time if ($cur_x != $args->{old_x} || $cur_y != $args->{old_y});
						debug "Route - next step moving to ($args->{new_x}, $args->{new_y}), index $args->{index}, $stepsleft steps left\n", "route";
						move($args->{new_x}, $args->{new_y}, $args->{attackID});
					}
				} else {
					# No more points to cover
					if ($args->{notifyUponArrival}) {
 						message T("Destination reached.\n"), "success";
					} else {
						debug "Destination reached.\n", "route";
					}
					AI::dequeue;
				}
			}

		} else {
			debug "Unexpected route stage [$args->{stage}] occured.\n", "route";
			AI::dequeue;
		}
	}
}

####### MAPROUTE #######
sub processMapRouteAI {
	if ( AI::action eq "mapRoute" && $field{name} && $char->{pos_to}{x} ne '' && $char->{pos_to}{y} ne '' ) {
		my $args = AI::args;

		if ($args->{stage} eq '') {
			$args->{'budget'} = $config{'route_maxWarpFee'} eq '' ?
				'' :
				$config{'route_maxWarpFee'} > $chars[$config{'char'}]{'zenny'} ?
					$chars[$config{'char'}]{'zenny'} :
					$config{'route_maxWarpFee'};
			delete $args->{'done'};
			delete $args->{'found'};
			delete $args->{'mapChanged'};
			delete $args->{'openlist'};
			delete $args->{'closelist'};
			undef @{$args->{'mapSolution'}};
			$args->{'dest'}{'field'} = {};
			getField($args->{dest}{map}, $args->{dest}{field});

			# Initializes the openlist with portals walkable from the starting point
			foreach my $portal (keys %portals_lut) {
				next if $portals_lut{$portal}{'source'}{'map'} ne $field{'name'};
				if ( ai_route_getRoute(\@{$args->{solution}}, \%field, $char->{pos_to}, \%{$portals_lut{$portal}{'source'}}) ) {
					foreach my $dest (keys %{$portals_lut{$portal}{'dest'}}) {
						my $penalty = int(($portals_lut{$portal}{'dest'}{$dest}{'steps'} ne '') ? $routeWeights{'NPC'} : $routeWeights{'PORTAL'});
						$args->{'openlist'}{"$portal=$dest"}{'walk'} = $penalty + scalar @{$args->{'solution'}};
						$args->{'openlist'}{"$portal=$dest"}{'zenny'} = $portals_lut{$portal}{'dest'}{$dest}{'cost'};
					}
				}
			}
			$args->{'stage'} = 'Getting Map Solution';

		} elsif ( $args->{stage} eq 'Getting Map Solution' ) {
			$timeout{'ai_route_calcRoute'}{'time'} = time;
			while (!$args->{'done'} && !timeOut(\%{$timeout{'ai_route_calcRoute'}})) {
				ai_mapRoute_searchStep($args);
			}
			if ($args->{'found'}) {
				$args->{'stage'} = 'Traverse the Map Solution';
				delete $args->{'openlist'};
				delete $args->{'solution'};
				delete $args->{'closelist'};
				delete $args->{'dest'}{'field'};
				debug "Map Solution Ready for traversal.\n", "route";
			} elsif ($args->{'done'}) {
				my $destpos = "$args->{dest}{pos}{x},$args->{dest}{pos}{y}";
				$destpos = "($destpos)" if ($destpos ne "");
				warning TF("Unable to calculate how to walk from [%s(%s,%s)] " .
					"to [%s%s] (no map solution).\n", $field{name}, $char->{pos_to}{x}, $char->{pos_to}{y}, $args->{dest}{map}, ${destpos}), "route";
				AI::dequeue;
                    if ($config{route_escape_unknownMap}) {
				   $timeout{ai_route_escape}{time} = time;
				   AI::queue("escape");
       			}
			}

		} elsif ( $args->{stage} eq 'Traverse the Map Solution' ) {

			my @solution;
			unless (@{$args->{'mapSolution'}}) {
				# mapSolution is now empty
				AI::dequeue;
				debug "Map Router is finish traversing the map solution\n", "route";

			} elsif ( $field{'name'} ne $args->{'mapSolution'}[0]{'map'}
				|| ( $args->{mapChanged} && !$args->{teleport} ) ) {
				# Solution Map does not match current map
				debug "Current map $field{'name'} does not match solution [ $args->{'mapSolution'}[0]{'portal'} ].\n", "route";
				delete $args->{'substage'};
				delete $args->{'timeout'};
				delete $args->{'mapChanged'};
				shift @{$args->{'mapSolution'}};

			} elsif ( $args->{'mapSolution'}[0]{'steps'} ) {
				# If current solution has conversation steps specified
				if ( $args->{'substage'} eq 'Waiting for Warp' ) {
					$args->{'timeout'} = time unless $args->{'timeout'};
					if (timeOut($args->{'timeout'}, $timeout{ai_route_npcTalk}{timeout} || 10) ||
					    $ai_v{npc_talk}{talk} eq 'close') {
						# We waited for 10 seconds and got nothing
						delete $args->{'substage'};
						delete $args->{'timeout'};
						if (++$args->{'mapSolution'}[0]{'retry'} >= ($config{route_maxNpcTries} || 5)) {
							# NPC sequence is a failure
							# We delete that portal and try again
							delete $portals_lut{"$args->{'mapSolution'}[0]{'map'} $args->{'mapSolution'}[0]{'pos'}{'x'} $args->{'mapSolution'}[0]{'pos'}{'y'}"};
 							warning TF("Unable to talk to NPC at %s (%s,%s).\n", $field{'name'}, $ai_seq_args[0]{'mapSolution'}[0]{'pos'}{'x'}, $ai_seq_args[0]{'mapSolution'}[0]{'pos'}{'y'}), "route";
							$args->{'stage'} = '';	# redo MAP router
						}
					}

				} elsif (distance($chars[$config{'char'}]{'pos_to'}, $args->{'mapSolution'}[0]{'pos'}) <= 10) {
					my ($from,$to) = split /=/, $args->{'mapSolution'}[0]{'portal'};
					if ($chars[$config{'char'}]{'zenny'} >= $portals_lut{$from}{'dest'}{$to}{'cost'}) {
						#we have enough money for this service
						$args->{'substage'} = 'Waiting for Warp';
						$args->{'old_x'} = $chars[$config{'char'}]{'pos_to'}{'x'};
						$args->{'old_y'} = $chars[$config{'char'}]{'pos_to'}{'y'};
						$args->{'old_map'} = $field{'name'};
						ai_talkNPC($args->{'mapSolution'}[0]{'pos'}{'x'}, $args->{'mapSolution'}[0]{'pos'}{'y'}, $args->{'mapSolution'}[0]{'steps'} );
					} else {
 						error TF("Insufficient zenny to pay for service at %s (%s,%s).\n", $field{'name'}, $ai_seq_args[0]{'mapSolution'}[0]{'pos'}{'x'}, $ai_seq_args[0]{'mapSolution'}[0]{'pos'}{'y'}), "route";
						$args->{'stage'} = ''; #redo MAP router
					}

				} elsif ( $args->{'maxRouteTime'} && time - $args->{'time_start'} > $args->{'maxRouteTime'} ) {
					# we spent too long a time
					debug "We spent too much time; bailing out.\n", "route";
					AI::dequeue;

				} elsif ( ai_route_getRoute( \@solution, \%field, $char->{pos_to}, $args->{mapSolution}[0]{pos} ) ) {
					# NPC is reachable from current position
					# >> Then "route" to it
					debug "Walking towards the NPC\n", "route";
					ai_route($args->{'mapSolution'}[0]{'map'}, $args->{'mapSolution'}[0]{'pos'}{'x'}, $args->{'mapSolution'}[0]{'pos'}{'y'},
						attackOnRoute => $args->{'attackOnRoute'},
						maxRouteTime => $args->{'maxRouteTime'},
						distFromGoal => 10,
						noSitAuto => $args->{'noSitAuto'},
						_solution => \@solution,
						_internal => 1);

				} else {
					#Error, NPC is not reachable from current pos
 					debug "CRITICAL ERROR: NPC is not reachable from current location.\n", "route";
 					error TF("Unable to walk from %s (%s,%s) to NPC at (%s,%s).\n", $field{'name'}, $chars[$config{'char'}]{'pos_to'}{'x'}, $chars[$config{'char'}]{'pos_to'}{'y'}, $ai_seq_args[0]{'mapSolution'}[0]{'pos'}{'x'}, $ai_seq_args[0]{'mapSolution'}[0]{'pos'}{'y'}), "route";
					shift @{$args->{'mapSolution'}};
				}

			} elsif ( $args->{'mapSolution'}[0]{'portal'} eq "$args->{'mapSolution'}[0]{'map'} $args->{'mapSolution'}[0]{'pos'}{'x'} $args->{'mapSolution'}[0]{'pos'}{'y'}=$args->{'mapSolution'}[0]{'map'} $args->{'mapSolution'}[0]{'pos'}{'x'} $args->{'mapSolution'}[0]{'pos'}{'y'}" ) {
				# This solution points to an X,Y coordinate
				my $distFromGoal = $args->{'pyDistFromGoal'} ? $args->{'pyDistFromGoal'} : ($args->{'distFromGoal'} ? $args->{'distFromGoal'} : 0);
				if ( $distFromGoal + 2 > distance($chars[$config{'char'}]{'pos_to'}, $args->{'mapSolution'}[0]{'pos'})) {
					#We need to specify +2 because sometimes the exact spot is occupied by someone else
					shift @{$args->{'mapSolution'}};

				} elsif ( $args->{'maxRouteTime'} && time - $args->{'time_start'} > $args->{'maxRouteTime'} ) {
					#we spent too long a time
					debug "We spent too much time; bailing out.\n", "route";
					AI::dequeue;

				} elsif ( ai_route_getRoute( \@solution, \%field, $chars[$config{'char'}]{'pos_to'}, $args->{'mapSolution'}[0]{'pos'} ) ) {
					# X,Y is reachable from current position
					# >> Then "route" to it
					ai_route($args->{'mapSolution'}[0]{'map'}, $args->{'mapSolution'}[0]{'pos'}{'x'}, $args->{'mapSolution'}[0]{'pos'}{'y'},
						attackOnRoute => $args->{'attackOnRoute'},
						maxRouteTime => $args->{'maxRouteTime'},
						distFromGoal => $args->{'distFromGoal'},
						pyDistFromGoal => $args->{'pyDistFromGoal'},
						noSitAuto => $args->{'noSitAuto'},
						_solution => \@solution,
						_internal => 1);

				} else {
 					warning TF("No LOS from %s (%s,%s) to Final Destination at (%s,%s).\n", $field{'name'}, $chars[$config{'char'}]{'pos_to'}{'x'}, $chars[$config{'char'}]{'pos_to'}{'y'}, $ai_seq_args[0]{'mapSolution'}[0]{'pos'}{'x'}, $ai_seq_args[0]{'mapSolution'}[0]{'pos'}{'y'}), "route";
 					error TF("Cannot reach (%s,%s) from current position.\n", $ai_seq_args[0]{'mapSolution'}[0]{'pos'}{'x'}, $ai_seq_args[0]{'mapSolution'}[0]{'pos'}{'y'}), "route";
					shift @{$args->{'mapSolution'}};
				}

			} elsif ( $portals_lut{"$args->{'mapSolution'}[0]{'map'} $args->{'mapSolution'}[0]{'pos'}{'x'} $args->{'mapSolution'}[0]{'pos'}{'y'}"}{'source'} ) {
				# This is a portal solution

				if ( 2 > distance($char->{pos_to}, $args->{mapSolution}[0]{pos}) ) {
					# Portal is within 'Enter Distance'
					$timeout{'ai_portal_wait'}{'timeout'} = $timeout{'ai_portal_wait'}{'timeout'} || 0.5;
					if ( timeOut($timeout{'ai_portal_wait'}) ) {
						sendMove(int($args->{'mapSolution'}[0]{'pos'}{'x'}), int($args->{'mapSolution'}[0]{'pos'}{'y'}) );
						$timeout{'ai_portal_wait'}{'time'} = time;
					}

				} else {
					my $walk = 1;

					# Teleport until we're close enough to the portal
					$args->{teleport} = $config{route_teleport} if (!defined $args->{teleport});

					if ($args->{teleport} && !$cities_lut{"$field{name}.rsw"}
					&& !existsInList($config{route_teleport_notInMaps}, $field{name})
					&& ( !$config{route_teleport_maxTries} || $args->{teleportTries} <= $config{route_teleport_maxTries} )) {
						my $minDist = $config{route_teleport_minDistance};

						if ($args->{mapChanged}) {
							undef $args->{sentTeleport};
							undef $args->{mapChanged};
						}

						if (!$args->{sentTeleport}) {
							# Find first inter-map portal
							my $portal;
							for my $x (@{$args->{mapSolution}}) {
								$portal = $x;
								last unless $x->{map} eq $x->{dest_map};
							}

							my $dist = new PathFinding(
								start => $char->{pos_to},
								dest => $portal->{pos},
								field => \%field
							)->runcount;
							debug "Distance to portal ($portal->{portal}) is $dist\n", "route_teleport";

							if ($dist <= 0 || $dist > $minDist) {
								if ($dist > 0 && $config{route_teleport_maxTries} && $args->{teleportTries} >= $config{route_teleport_maxTries}) {
									debug "Teleported $config{route_teleport_maxTries} times. Falling back to walking.\n", "route_teleport";
								} else {
									message TF("Attempting to teleport near portal, try #%s\n", ($args->{teleportTries} + 1)), "route_teleport";
									if (!useTeleport(1)) {
										$args->{teleport} = 0;
									} else {
										$walk = 0;
										$args->{sentTeleport} = 1;
										$args->{teleportTime} = time;
										$args->{teleportTries}++;
									}
								}
							}

						} elsif (timeOut($args->{teleportTime}, 4)) {
							debug "Unable to teleport; falling back to walking.\n", "route_teleport";
							$args->{teleport} = 0;
						} else {
							$walk = 0;
						}
					}

					if ($walk) {
						if ( ai_route_getRoute( \@solution, \%field, $char->{pos_to}, $args->{mapSolution}[0]{pos} ) ) {
							debug "portal within same map\n", "route";
							# Portal is reachable from current position
							# >> Then "route" to it
							debug "Portal route attackOnRoute = $args->{attackOnRoute}\n", "route";
							$args->{teleportTries} = 0;
							ai_route($args->{'mapSolution'}[0]{'map'}, $args->{'mapSolution'}[0]{'pos'}{'x'}, $args->{'mapSolution'}[0]{'pos'}{'y'},
								attackOnRoute => $args->{attackOnRoute},
								maxRouteTime => $args->{maxRouteTime},
								noSitAuto => $args->{noSitAuto},
								tags => $args->{tags},
								_solution => \@solution,
								_internal => 1);

						} else {
 							warning TF("No LOS from %s (%s,%s) to Portal at (%s,%s).\n", $field{'name'}, $chars[$config{'char'}]{'pos_to'}{'x'}, $chars[$config{'char'}]{'pos_to'}{'y'}, $ai_seq_args[0]{'mapSolution'}[0]{'pos'}{'x'}, $ai_seq_args[0]{'mapSolution'}[0]{'pos'}{'y'}), "route";
 							error T("Cannot reach portal from current position\n"), "route";
							shift @{$args->{mapSolution}};
						}
					}
				}
			}
		}
	}
}

##### AUTO STORAGE #####
sub processAutoStorage {
	# storageAuto - chobit aska 20030128
	if (AI::is("", "route", "sitAuto", "follow")
		  && $config{storageAuto} && ($config{storageAuto_npc} ne "" || $config{storageAuto_useChatCommand})
		  && !$ai_v{sitAuto_forcedBySitCommand}
		  && (($config{'itemsMaxWeight_sellOrStore'} && percent_weight($char) >= $config{'itemsMaxWeight_sellOrStore'})
		      || (!$config{'itemsMaxWeight_sellOrStore'} && percent_weight($char) >= $config{'itemsMaxWeight'}))
		  && !AI::inQueue("storageAuto") && time > $ai_v{'inventory_time'}) {

		# Initiate autostorage when the weight limit has been reached
		my $routeIndex = AI::findAction("route");
		my $attackOnRoute = 2;
		$attackOnRoute = AI::args($routeIndex)->{attackOnRoute} if (defined $routeIndex);
		# Only autostorage when we're on an attack route, or not moving
		if ($attackOnRoute > 1 && ai_storageAutoCheck()) {
			message T("Auto-storaging due to excess weight\n");
			AI::queue("storageAuto");
		}

	} elsif (AI::is("", "route", "attack")
		  && $config{storageAuto}
		  && ($config{storageAuto_npc} ne "" || $config{storageAuto_useChatCommand})
		  && !$ai_v{sitAuto_forcedBySitCommand}
		  && !AI::inQueue("storageAuto")
		  && @{$char->{inventory}} > 0) {

		# Initiate autostorage when we're low on some item, and getAuto is set
		my $found;
		my $i;
		for ($i = 0; exists $config{"getAuto_$i"}; $i++) {
			my $invIndex = findIndexString_lc($char->{inventory}, "name", $config{"getAuto_$i"});
			if ($config{"getAuto_${i}_minAmount"} ne "" &&
			    $config{"getAuto_${i}_maxAmount"} ne "" &&
			    !$config{"getAuto_${i}_passive"} &&
			    (!defined($invIndex) ||
				 ($char->{inventory}[$invIndex]{amount} <= $config{"getAuto_${i}_minAmount"} &&
				  $char->{inventory}[$invIndex]{amount} < $config{"getAuto_${i}_maxAmount"})
			    )
			) {
				if ($storage{opened} && findKeyString(\%storage, "name", $config{"getAuto_$i"}) eq '') {
					if ($config{"getAuto_${i}_dcOnEmpty"}) {
 						message TF("Disconnecting on empty %s!\n", $config{"getAuto_$i"});
						chatLog("k", TF("Disconnecting on empty %s!\n", $config{"getAuto_$i"}));
						quit();
					}
				} else {
					$found = 1;
				}
				last;
			}
		}

		my $routeIndex = AI::findAction("route");
		my $attackOnRoute;
		$attackOnRoute = AI::args($routeIndex)->{attackOnRoute} if (defined $routeIndex);

		# Only autostorage when we're on an attack route, or not moving
		if ((!defined($routeIndex) || $attackOnRoute > 1) && $found &&
			@{$char->{inventory}} > 0) {
	 		message TF("Auto-storaging due to insufficient %s\n", $config{"getAuto_$i"});
			AI::queue("storageAuto");
		}
		$timeout{'ai_storageAuto'}{'time'} = time;
	}


	if (AI::action eq "storageAuto" && AI::args->{done}) {
		# Autostorage finished; trigger sellAuto unless autostorage was already triggered by it
		my $forcedBySell = AI::args->{forcedBySell};
		my $forcedByBuy = AI::args->{forcedByBuy};
		AI::dequeue;
		if ($forcedByBuy) {
			AI::queue("sellAuto", {forcedByBuy => 1});
		} elsif (!$forcedBySell && ai_sellAutoCheck() && $config{sellAuto}) {
			AI::queue("sellAuto", {forcedByStorage => 1});
		}

	} elsif (AI::action eq "storageAuto" && timeOut($timeout{'ai_storageAuto'})) {
		# Main autostorage block
		my $args = AI::args;

		my $do_route;

		if (!$config{storageAuto_useChatCommand}) {
			# Stop if the specified NPC is invalid
			$args->{npc} = {};
			getNPCInfo($config{'storageAuto_npc'}, $args->{npc});
			if (!defined($args->{npc}{ok})) {
				$args->{done} = 1;
				return;
			}

			# Determine whether we have to move to the NPC
			if ($field{'name'} ne $args->{npc}{map}) {
				$do_route = 1;
			} else {
				my $distance = distance($args->{npc}{pos}, $char->{pos_to});
				if ($distance > $config{'storageAuto_distance'}) {
					$do_route = 1;
				}
			}

			if ($do_route) {
				if ($args->{warpedToSave} && !$args->{mapChanged} && !timeOut($args->{warpStart}, 8)) {
					undef $args->{warpedToSave};
				}

				# If warpToBuyOrSell is set, warp to saveMap if we haven't done so
				if ($config{'saveMap'} ne "" && $config{'saveMap_warpToBuyOrSell'} && !$args->{warpedToSave}
				    && !$cities_lut{$field{'name'}.'.rsw'} && $config{'saveMap'} ne $field{name}) {
					$args->{warpedToSave} = 1;
					# If we still haven't warped after a certain amount of time, fallback to walking
					$args->{warpStart} = time unless $args->{warpStart};
					message T("Teleporting to auto-storage\n"), "teleport";
					useTeleport(2);
					$timeout{'ai_storageAuto'}{'time'} = time;
				} else {
					# warpToBuyOrSell is not set, or we've already warped, or timed out. Walk to the NPC
					message TF("Calculating auto-storage route to: %s(%s): %s, %s\n", $maps_lut{$args->{npc}{map}.'.rsw'}, $args->{npc}{map}, $args->{npc}{pos}{x}, $args->{npc}{pos}{y}), "route";
					ai_route($args->{npc}{map}, $args->{npc}{pos}{x}, $args->{npc}{pos}{y},
						 attackOnRoute => 1,
						 distFromGoal => $config{'storageAuto_distance'});
				}
			}
		}
		if (!$do_route) {
			# Talk to NPC if we haven't done so
			if (!defined($args->{sentStore})) {
				if ($config{storageAuto_useChatCommand}) {
					sendMessage($net, "c", $config{storageAuto_useChatCommand});
				} else {
					if ($config{'storageAuto_npc_type'} eq "" || $config{'storageAuto_npc_type'} eq "1") {
						warning T("Warning storageAuto has changed. Please read News.txt\n") if ($config{'storageAuto_npc_type'} eq "");
						$config{'storageAuto_npc_steps'} = "c r1 n";
						debug "Using standard iRO npc storage steps.\n", "npc";
					} elsif ($config{'storageAuto_npc_type'} eq "2") {
						$config{'storageAuto_npc_steps'} = "c c r1 n";
						debug "Using iRO comodo (location) npc storage steps.\n", "npc";
					} elsif ($config{'storageAuto_npc_type'} eq "3") {
						message T("Using storage steps defined in config.\n"), "info";
					} elsif ($config{'storageAuto_npc_type'} ne "" && $config{'storageAuto_npc_type'} ne "1" && $config{'storageAuto_npc_type'} ne "2" && $config{'storageAuto_npc_type'} ne "3") {
						error T("Something is wrong with storageAuto_npc_type in your config.\n");
					}

					ai_talkNPC($args->{npc}{pos}{x}, $args->{npc}{pos}{y}, $config{'storageAuto_npc_steps'});
				}

				delete $ai_v{temp}{storage_opened};
				$args->{sentStore} = 1;

				# NPC talk retry
				$AI::Timeouts::storageOpening = time;
				$timeout{'ai_storageAuto'}{'time'} = time;
				return;
			}

			if (!defined $ai_v{temp}{storage_opened}) {
				# NPC talk retry
				if (timeOut($AI::Timeouts::storageOpening, 40)) {
					undef $args->{sentStore};
					debug "Retry talking to autostorage NPC.\n", "npc";
				}

				# Storage not yet opened; stop and wait until it's open
				return;
			}

			if (!$args->{getStart}) {
				$args->{done} = 1;

				# inventory to storage
				$args->{nextItem} = 0 unless $args->{nextItem};
				for (my $i = $args->{nextItem}; $i < @{$char->{inventory}}; $i++) {
					my $item = $char->{inventory}[$i];
					next unless ($item && %{$item});
					next if $item->{equipped};
					next if ($item->{broken} && $item->{type} == 7); # dont store pet egg in use

					my $control = items_control($item->{name});

					debug "AUTOSTORAGE: $item->{name} x $item->{amount} - store = $control->{storage}, keep = $control->{keep}\n", "storage";
					if ($control->{storage} && $item->{amount} > $control->{keep}) {
						if ($args->{lastIndex} == $item->{index} &&
						    timeOut($timeout{'ai_storageAuto_giveup'})) {
							return;
						} elsif ($args->{lastIndex} != $item->{index}) {
							$timeout{ai_storageAuto_giveup}{time} = time;
						}
						undef $args->{done};
						$args->{lastIndex} = $item->{index};
						sendStorageAdd($item->{index}, $item->{amount} - $control->{keep});
						$timeout{ai_storageAuto}{time} = time;
						$args->{nextItem} = $i + 1;
						return;
					}
				}

				# cart to storage
				# we don't really need to check if we have a cart
				# if we don't have one it will not find any items to loop through
				$args->{cartNextItem} = 0 unless $args->{cartNextItem};
				for (my $i = $args->{cartNextItem}; $i < @{$cart{inventory}}; $i++) {
					my $item = $cart{inventory}[$i];
					next unless ($item && %{$item});

					my $control = items_control($item->{name});

					debug "AUTOSTORAGE (cart): $item->{name} x $item->{amount} - store = $control->{storage}, keep = $control->{keep}\n", "storage";
					# store from cart as well as inventory if the flag is equal to 2
					if ($control->{storage} == 2 && $item->{amount} > $control->{keep}) {
						if ($args->{cartLastIndex} == $item->{index} &&
						    timeOut($timeout{'ai_storageAuto_giveup'})) {
							return;
						} elsif ($args->{cartLastIndex} != $item->{index}) {
							$timeout{ai_storageAuto_giveup}{time} = time;
						}
						undef $args->{done};
						$args->{cartLastIndex} = $item->{index};
						sendStorageAddFromCart($item->{index}, $item->{amount} - $control->{keep});
						$timeout{ai_storageAuto}{time} = time;
						$args->{cartNextItem} = $i + 1;
						return;
					}
				}

				if ($args->{done}) {
					# plugins can hook here and decide to keep storage open longer
					my %hookArgs;
					Plugins::callHook("AI_storage_done", \%hookArgs);
					undef $args->{done} if ($hookArgs{return});
				}
			}


			# getAuto begin

			if (!$args->{getStart} && $args->{done} == 1) {
				$args->{getStart} = 1;
				undef $args->{done};
				$args->{index} = 0;
				$args->{retry} = 0;
				return;
			}

			if (defined($args->{getStart}) && $args->{done} != 1) {
				while (exists $config{"getAuto_$args->{index}"}) {
					if (!$config{"getAuto_$args->{index}"}) {
						$args->{index}++;
						next;
					}

					my %item;
					$item{name} = $config{"getAuto_$args->{index}"};
					$item{inventory}{index} = findIndexString_lc(\@{$chars[$config{char}]{inventory}}, "name", $item{name});
					$item{inventory}{amount} = ($item{inventory}{index} ne "") ? $chars[$config{char}]{inventory}[$item{inventory}{index}]{amount} : 0;
					$item{storage}{index} = findKeyString(\%storage, "name", $item{name});
					$item{storage}{amount} = ($item{storage}{index} ne "")? $storage{$item{storage}{index}}{amount} : 0;
					$item{max_amount} = $config{"getAuto_$args->{index}"."_maxAmount"};
					$item{amount_needed} = $item{max_amount} - $item{inventory}{amount};

					# Calculate the amount to get
					if ($item{amount_needed} > 0) {
						$item{amount_get} = ($item{storage}{amount} >= $item{amount_needed})? $item{amount_needed} : $item{storage}{amount};
					}

					# Try at most 3 times to get the item
					if (($item{amount_get} > 0) && ($args->{retry} < 3)) {
						message TF("Attempt to get %s x %s from storage, retry: %s\n", $item{amount_get}, $item{name}, $ai_seq_args[0]{retry}), "storage", 1;
						sendStorageGet($item{storage}{index}, $item{amount_get});
						$timeout{ai_storageAuto}{time} = time;
						$args->{retry}++;
						return;

						# we don't inc the index when amount_get is more then 0, this will enable a way of retrying
						# on next loop if it fails this time
					}

					if ($item{storage}{amount} < $item{amount_needed}) {
						warning TF("storage: %s out of stock\n", $item{name});
					}

					if (!$config{relogAfterStorage} && $args->{retry} >= 3 && !$args->{warned}) {
						# We tried 3 times to get the item and failed.
						# There is a weird server bug which causes this to happen,
						# but I can't reproduce it. This can be worked around by
						# relogging in after autostorage.
						warning T("Kore tried to get an item from storage 3 times, but failed.\n" .
							  "This problem could be caused by a server bug.\n" .
							  "To work around this problem, set 'relogAfterStorage' to 1, and relogin.\n");
						$args->{warned} = 1;
					}

					# We got the item, or we tried 3 times to get it, but failed.
					# Increment index and process the next item.
					$args->{index}++;
					$args->{retry} = 0;
				}
			}

			sendStorageClose() unless $config{storageAuto_keepOpen};
			if (percent_weight($char) >= $config{'itemsMaxWeight_sellOrStore'} && ai_storageAutoCheck()) {
				error T("Character is still overweight after storageAuto (storage is full?)\n");
				if ($config{dcOnStorageFull}) {
					error T("Disconnecting on storage full!\n");
					chatLog("k", T("Disconnecting on storage full!\n"));
					quit();
				}
			}
			if ($config{'relogAfterStorage'}) {
				writeStorageLog(0);
				relog();
			}
			$args->{done} = 1;
		}
	}
}

##### AUTO-EQUIP #####
sub processAutoEquip {
	Benchmark::begin("ai_autoEquip") if DEBUG;
	if ((AI::isIdle || AI::is(qw(route mapRoute follow sitAuto skill_use take items_gather items_take attack)))
	  && timeOut($timeout{ai_item_equip_auto}) && time > $ai_v{'inventory_time'}) {

		my $ai_index_attack = AI::findAction("attack");

		my $monster;
		if (defined $ai_index_attack) {
			my $ID = AI::args($ai_index_attack)->{ID};
			$monster = $monsters{$ID};
		}

		# we will create a list of items to equip
		my %eq_list;

		for (my $i = 0; exists $config{"equipAuto_$i"}; $i++) {
			if ((!$config{"equipAuto_${i}_weight"} || $char->{percent_weight} >= $config{"equipAuto_$i" . "_weight"})
			 && (!$config{"equipAuto_${i}_whileSitting"} || ($config{"equipAuto_${i}_whileSitting"} && $char->{sitting}))
			 && (!$config{"equipAuto_${i}_target"} || (defined $monster && existsInList($config{"equipAuto_$i" . "_target"}, $monster->{name})))
			 && checkMonsterCondition("equipAuto_${i}_target", $monster)
			 && checkSelfCondition("equipAuto_$i")
			 && Item::scanConfigAndCheck("equipAuto_$i")
			) {
				foreach my $slot (values %equipSlot_lut) {
					if (exists $config{"equipAuto_$i"."_$slot"}) {
						debug "Equip $slot with ".$config{"equipAuto_$i"."_$slot"}."\n";
						$eq_list{$slot} = $config{"equipAuto_$i"."_$slot"} if (!$eq_list{$slot});
					}
				}
			}
		}

		if (%eq_list) {
			debug "Auto-equipping items\n", "equipAuto";
			Item::bulkEquip(\%eq_list);
		}
		$timeout{ai_item_equip_auto}{time} = time;

	}
	Benchmark::end("ai_autoEquip") if DEBUG;
}

##### AUTO-ATTACK #####
sub processAutoAttack {
	# The auto-attack logic is as follows:
	# 1. Generate a list of monsters that we are allowed to attack.
	# 2. Pick the "best" monster out of that list, and attack it.

	Benchmark::begin("ai_autoAttack") if DEBUG;

	if ((AI::isIdle || AI::is(qw/route follow sitAuto take items_gather items_take/) || (AI::action eq "mapRoute" && AI::args->{stage} eq 'Getting Map Solution'))
	     # Don't auto-attack monsters while taking loot, and itemsTake/GatherAuto >= 2
	  && !($config{'itemsTakeAuto'} >= 2 && AI::is("take", "items_take"))
	  && !($config{'itemsGatherAuto'} >= 2 && AI::is("take", "items_gather"))
	  && timeOut($timeout{ai_attack_auto})
	  && (!$config{teleportAuto_search} || $ai_v{temp}{searchMonsters} >= $config{teleportAuto_search})
	  && (!$config{attackAuto_notInTown} || !$cities_lut{$field{name}.'.rsw'})) {

		# If we're in tanking mode, only attack something if the person we're tanking for is on screen.
		my $foundTankee;
		if ($config{'tankMode'}) {
			foreach (@playersID) {
				next if (!$_);
				if ($config{'tankModeTarget'} eq $players{$_}{'name'}) {
					$foundTankee = 1;
					last;
				}
			}
		}

		my $attackTarget;
		my $priorityAttack;

		if (!$config{'tankMode'} || $foundTankee) {
			# This variable controls how far monsters must be away from portals and players.
			my $portalDist = $config{'attackMinPortalDistance'} || 4;
			my $playerDist = $config{'attackMinPlayerDistance'};
			$playerDist = 1 if ($playerDist < 1);

			# Detect whether we are currently in follow mode
			my $following;
			my $followID;
			if (defined(my $followIndex = AI::findAction("follow"))) {
				$following = AI::args($followIndex)->{following};
				$followID = AI::args($followIndex)->{ID};
			}

			my $routeIndex = AI::findAction("route");
			$routeIndex = AI::findAction("mapRoute") if (!defined $routeIndex);
			my $attackOnRoute;
			if (defined $routeIndex) {
				$attackOnRoute = AI::args($routeIndex)->{attackOnRoute};
			} else {
				$attackOnRoute = 2;
			}


			### Step 1: Generate a list of all monsters that we are allowed to attack. ###
			my @aggressives;
			my @partyMonsters;
			my @cleanMonsters;

			# List aggressive monsters
			@aggressives = ai_getAggressives(1) if ($config{'attackAuto'} && $attackOnRoute);

			# There are two types of non-aggressive monsters. We generate two lists:
			foreach (@monstersID) {
				next if (!$_ || !checkMonsterCleanness($_));
				my $monster = $monsters{$_};
				# Ignore ignored monsters in mon_control.txt
				if ((my $control = mon_control($monster->{name}))) {
					next if ( ($control->{attack_auto} ne "" && $control->{attack_auto} <= 0)
						|| ($control->{attack_lvl} ne "" && $control->{attack_lvl} > $char->{lv})
						|| ($control->{attack_jlvl} ne "" && $control->{attack_jlvl} > $char->{lv_job})
						|| ($control->{attack_hp}  ne "" && $control->{attack_hp} > $char->{hp})
						|| ($control->{attack_sp}  ne "" && $control->{attack_sp} > $char->{sp})
						);
				}

				my $pos = calcPosition($monster);
				OpenKoreMod::autoAttack($monster) if (defined &OpenKoreMod::autoAttack);

				# List monsters that party members are attacking
				if ($config{attackAuto_party} && $attackOnRoute && !AI::is("take", "items_take")
				 && !$ai_v{sitAuto_forcedBySitCommand}
				 && (($monster->{dmgFromParty} && $config{attackAuto_party} != 2) ||
				     $monster->{dmgToParty} || $monster->{missedToParty})
				 && timeOut($monster->{attack_failed}, $timeout{ai_attack_unfail}{timeout})) {
					push @partyMonsters, $_;
					next;
				}

				# List monsters that the master is attacking
				if ($following && $config{'attackAuto_followTarget'} && $attackOnRoute && !AI::is("take", "items_take")
				 && ($monster->{dmgToPlayer}{$followID} || $monster->{dmgFromPlayer}{$followID} || $monster->{missedToPlayer}{$followID})
				 && timeOut($monster->{attack_failed}, $timeout{ai_attack_unfail}{timeout})) {
					push @partyMonsters, $_;
					next;
				}


				### List normal, non-aggressive monsters. ###

				# Ignore monsters that
				# - Have a status (such as poisoned), because there's a high chance
				#   they're being attacked by other players
				# - Are inside others' area spells (this includes being trapped).
				# - Are moving towards other players.
				# - Are behind a wall
				next if (( $monster->{statuses} && scalar(keys %{$monster->{statuses}}) )
					|| objectInsideSpell($monster)
					|| objectIsMovingTowardsPlayer($monster));
				if ($config{'attackCanSnipe'}) {
					next if (!checkLineSnipable($char->{pos_to}, $pos));
				} else {
					next if (!checkLineWalkable($char->{pos_to}, $pos));
				}

				my $safe = 1;
				if ($config{'attackAuto_onlyWhenSafe'}) {
					foreach (@playersID) {
						if ($_ && !$char->{party}{users}{$_}) {
							$safe = 0;
							last;
						}
					}
				}

				if (!AI::is(qw/sitAuto take items_gather items_take/)
				 && $config{'attackAuto'} >= 2 && !$ai_v{sitAuto_forcedBySitCommand}
				 && $attackOnRoute >= 2 && !$monster->{dmgFromYou} && $safe
				 && !positionNearPlayer($pos, $playerDist) && !positionNearPortal($pos, $portalDist)
				 && timeOut($monster->{attack_failed}, $timeout{ai_attack_unfail}{timeout})) {
					push @cleanMonsters, $_;
				}
			}


			### Step 2: Pick out the "best" monster ###

			my $myPos = calcPosition($char);
			my $highestPri;

			# Look for the aggressive monster that has the highest priority
			foreach (@aggressives) {
				my $monster = $monsters{$_};
				my $pos = calcPosition($monster);
				# Don't attack monsters near portals
				next if (positionNearPortal($pos, $portalDist));

				# Don't attack ignored monsters
				if ((my $control = mon_control($monster->{name}))) {
					next if ( ($control->{attack_auto} == -1)
						|| ($control->{attack_lvl} ne "" && $control->{attack_lvl} > $char->{lv})
						|| ($control->{attack_jlvl} ne "" && $control->{attack_jlvl} > $char->{lv_job})
						|| ($control->{attack_hp}  ne "" && $control->{attack_hp} > $char->{hp})
						|| ($control->{attack_sp}  ne "" && $control->{attack_sp} > $char->{sp})
						);
				}

				my $name = lc $monster->{name};
				if (defined($priority{$name}) && $priority{$name} > $highestPri) {
					$highestPri = $priority{$name};
				}
			}

			my $smallestDist;
			if (!defined $highestPri) {
				# If not found, look for the closest aggressive monster (without priority)
				foreach (@aggressives) {
					my $monster = $monsters{$_};
					my $pos = calcPosition($monster);
					# Don't attack monsters near portals
					next if (positionNearPortal($pos, $portalDist));

					# Don't attack ignored monsters
					if ((my $control = mon_control($monster->{name}))) {
						next if ( ($control->{attack_auto} == -1)
							|| ($control->{attack_lvl} ne "" && $control->{attack_lvl} > $char->{lv})
							|| ($control->{attack_jlvl} ne "" && $control->{attack_jlvl} > $char->{lv_job})
							|| ($control->{attack_hp}  ne "" && $control->{attack_hp} > $char->{hp})
							|| ($control->{attack_sp}  ne "" && $control->{attack_sp} > $char->{sp})
							);
					}

					if (!defined($smallestDist) || (my $dist = distance($myPos, $pos)) < $smallestDist) {
						$smallestDist = $dist;
						$attackTarget = $_;
					}
				}
			} else {
				# If found, look for the closest aggressive monster with the highest priority
				foreach (@aggressives) {
					my $monster = $monsters{$_};
					my $pos = calcPosition($monster);
					# Don't attack monsters near portals
					next if (positionNearPortal($pos, $portalDist));

					# Don't attack ignored monsters
					if ((my $control = mon_control($monster->{name}))) {
						next if ( ($control->{attack_auto} == -1)
							|| ($control->{attack_lvl} ne "" && $control->{attack_lvl} > $char->{lv})
							|| ($control->{attack_jlvl} ne "" && $control->{attack_jlvl} > $char->{lv_job})
							|| ($control->{attack_hp}  ne "" && $control->{attack_hp} > $char->{hp})
							|| ($control->{attack_sp}  ne "" && $control->{attack_sp} > $char->{sp})
							);
					}

					if (!defined($smallestDist) || (my $dist = distance($myPos, $pos)) < $smallestDist) {
						$smallestDist = $dist;
						$attackTarget = $_;
						$priorityAttack = 1;
					}
				}
			}

			if (!$attackTarget) {
				undef $smallestDist;
				# There are no aggressive monsters; look for the closest monster that a party member/master is attacking
				foreach (@partyMonsters) {
					my $monster = $monsters{$_};
					my $pos = calcPosition($monster);
					if (!defined($smallestDist) || (my $dist = distance($myPos, $pos)) < $smallestDist) {
						$smallestDist = $dist;
						$attackTarget = $_;
					}
				}
			}

			if (!$attackTarget) {
				# No party monsters either; look for the closest, non-aggressive monster that:
				# 1) nobody's attacking
				# 2) has the highest priority

				undef $smallestDist;
				foreach (@cleanMonsters) {
					my $monster = $monsters{$_};
					next unless $monster;
					my $pos = calcPosition($monster);
					my $dist = distance($myPos, $pos);
					my $name = lc $monster->{name};

					if (!defined($smallestDist) || $priority{$name} > $highestPri
					  || ( $priority{$name} == $highestPri && $dist < $smallestDist )) {
						$smallestDist = $dist;
						$attackTarget = $_;
						$highestPri = $priority{$monster};
					}
				}
			}
		}
		# If an appropriate monster's found, attack it. If not, wait ai_attack_auto secs before searching again.
		if ($attackTarget) {
			ai_setSuspend(0);
			attack($attackTarget, $priorityAttack);
		} else {
			$timeout{'ai_attack_auto'}{'time'} = time;
		}
	}

	Benchmark::end("ai_autoAttack") if DEBUG;
}

1;
