=========================
### OpenKore 1.9.3 (beta)
=========================

To Fix:
- XKore2 is not acting like a real server, it doesn't send complete
  informations to the client. Connecting to XKore2 from another kore would
  fail. 

Bug fixes:
- isSelfSkill now works in monsterSkill blocks.
- Fixed homunculus_tankMode.
- Fixed inability to detect evolved homunculus state.

New config options:
- dealAuto_names <list of player names>
    If non-empty and dealAuto is set to 2 or 3, then bot will only deal with
    players on the list. (Other players will be treated as dealAuto 0.)

=========================
### OpenKore 1.9.2 (beta)
=========================

*** INCOMPATIBLE CHANGES ***:
- You need to download the latest responses.txt (in the config pack)
  to use the new 'exp' and 'version' chat commands.

Credits:
- Molag: Ayothaya portals contributions.
- DarkShado: XileRO server information updates.
- johnny: Homunculus skills.
- piroJOKE: field file contributions.
- cloud2squall: server information contributions.
- n0rd: support for compressed field files.

Bug fixes:
- Fixed a crash when unequipping items (bug #16)
- Fixed an auto-completion crash bug (bug #24)
- Fixed the "Can't store CODE items" bug (bug #37)

New features:
- Added AI::Homunculus module for homunculus AI support with automated
	homunculus feeding, following, and attacking (see new config options and
	commands).
- Support for homunculus skills in skills.txt (use normal skill blocks to use
	them).
- Add support for new vRO. Use serverType 10.
- Added teleportAuto_lostTarget, teleport when target is lost.
- Added a mob-training control. Use attack flag 3 in mon_control.txt to
	activate this. More details are available at:
	http://forums.openkore.com/viewtopic.php?p=134002
- Added command chaining, preform multiple commands in 1 line. the " ; "
	character is used to delimit the command.s
	Example: c watch out im using an item now;is 0;c see, i used it!
- Added Aegis 10.4 new classes support.
- Added Taekwon mission support.
- Added manualAI Where autoskills could be executed in ai manual mode.
	for more information : http://forums.openkore.com/viewtopic.php?t=24513

New config options:
- attackChangeTarget <boolean flag>
    automatically change target to an aggressive monster if the target monster
	is not yet reached or damaged. This prevents you from continuously routing
	to your target while dragging a mob of aggressive monsters behind you.
- homunculus_followDistanceMax <distance>
- homunculus_followDistanceMin <distance>
    Kore and the homunculus will always try to keep within these distances from
	each other.
- homunculus_attackAuto <flag>
- homunculus_attackAuto_party <flag>
- homunculus_attackAuto_notInTown <boolean flag>
- homunculus_attackAuto_onlyWhenSafe <boolean flag>
- homunculus_attackDistance <distance>
- homunculus_attackMaxDistance <distance>
- homunculus_attackMaxRouteTime <seconds>
- homunculus_attackMinPlayerDistance <distance>
- homunculus_attackMinPortalDistance <distance>
- homunculus_attackCanSnipe <boolean flag>
- homunculus_attackCheckLOS <boolean flag>
- homunculus_attackNoGiveup <boolean flag>
    same as the attackAuto* counterparts.
- homunculus_attackChangeTarget <boolean flag>
    same as attackChangeTarget.
- homunculus_route_step <number>
    this option is required or your homunculus will not be able to move.
- homunculus_runFromTarget <boolean flag>
- homunculus_runFromTarget_dist <distance>
    these will mostly be not needed but they are still included for posterity.
- homunculus_tankMode <boolean flag>
- homunculus_tankModeTarget <player name>
    same as the tankMode* counterparts. You can use this so that your
	homunculus can tank you. Set homunculus_tankModeTarget to your character
	name.
- homunculus_teleportAuto_deadly <boolean flag>
- homunculus_teleportAuto_dropTarget <boolean flag>
- homunculus_teleportAuto_dropTargetKS <boolean flag>
- homunculus_teleportAuto_hp <percent hp>
- homunculus_teleportAuto_maxDmg <damage>
- homunculus_teleportAuto_maxDmgInLock <damage>
- homunculus_teleportAuto_totalDmg <damage>
- homunculus_teleportAuto_totalDmgInLock <damage>
- homunculus_teleportAuto_unstuck <boolean flag>
    same as the teleportAuto* counterparts.
- Shared Block Attributes: homunculus_hp <hp>[%] and homunculus_sp <sp>[%]
    same as the hp/sp block attributes. These are useful for using homunculus
	skills on your skill blocks.
- teleportAuto_lostHomunculus <boolean flag>
    instead of routing back to your lost homunculus (default), Kore will
	teleport to get the homunculus back.
- Shared Block Attribute: homunculus_dead <boolean flag>
    triggers the config block only if your homunculus died.
- teleportAuto_lostTarget <boolean flag>
	Makes the bot (attempt to) teleport after it lost its target, this to
	prevent it from locking onto the same target over and over in some cases.
- ignoreServerShutdown <boolean flag>
	Ignores the "server shutting down" error wich some servers tend to send
	(iRO for example).
	Don't use this unless you're 100% sure the errors are "fake".
- Shared Block Attribute: manualAI <flag>
	flag 0    auto only
	flag 1    manual only
	flag 2    auto or manual

New sys.txt options:
- sendAnonymousStatisticReport <boolean flag>
    tells whether OpenKore will report an anonymous usage report. Note that
	none of your sensitive information will be sent. More info is available at:
	http://www.openkore.com/statistics.php

New commands:
- homun <s|status|feed|move|standby|ai|aiv|skills>
	homun s       : displays homunculus status.
	homun feed    : manually feeds homunculus.
	homun move    : basic homunculus move command (similar to 'move' command).
	homun standby : basic homunculus standby command.
	homun ai      : homunculus AI management (similar to 'ai' command).
	homun aiv     : displays homunculus AI sequences.
	homun skills  : homunculus skills management (similar to 'skills' command).

New chat commands:
- exp [item|monster]
	behaves like the 'exp' console command, but it is used as a chat
	command.
	exp         : shows exp gain.
	exp item    : shows items gain.
	exp monster : shows killed monsters.
- version
	shows the OpenKore version.

Incompatible Changes:
- ; command separator replaced with ;;, so you can now use semicolons
  in chat (as long as they're not two in a row).

Internal:
- Updated $config{gameGuard} '2' behavior to adapt to bRO server.
- The Console::Other interface has been removed in favor of the Console::Unix
	interface. This only affects OpenKore when running on a Unix, such as
	Linux.
- Item has been renamed to Actor::Item for consistency.
- Receive.pm : monk_spirits is now known as revolving_entity
- Added Bullet support
- New 'disconnected' plugin hook, called when you get disconnected
  from the map server

--------------------------

For older news, please read:
http://www.openkore.com/misc/OldNews.txt
