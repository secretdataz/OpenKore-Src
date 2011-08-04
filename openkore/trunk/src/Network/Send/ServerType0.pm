#########################################################################
#  OpenKore - Network subsystem
#  This module contains functions for sending messages to the server.
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#########################################################################
# June 21 2007, this is the server type for:
# pRO (Philippines), except Sakray and Thor
# And many other servers.
# Servertype overview: http://www.openkore.com/wiki/index.php/ServerType
package Network::Send::ServerType0;

use strict;
use Time::HiRes qw(time);
use Digest::MD5;

use Network::Send ();
use base qw(Network::Send);
use Plugins;
use Globals qw($accountID $sessionID $sessionID2 $accountSex $char $charID %config %guild @chars $masterServer $syncSync);
use Log qw(debug);
use Misc qw(stripLanguageCode);
use Translation qw(T TF);
use I18N qw(bytesToString stringToBytes);
use Utils;
use Utils::Exceptions;
use Utils::Rijndael;

# to test zealotus bug
#use Data::Dumper;


sub new {
	my ($class) = @_;
	my $self = $class->SUPER::new(@_);
	
	my %packets = (
		'0064' => ['master_login', 'V Z24 Z24 C', [qw(version username password master_version)]],
		'0065' => ['game_login', 'a4 a4 a4 v C', [qw(accountID sessionID sessionID2 userLevel accountSex)]],
		'0066' => ['char_login', 'C', [qw(slot)]],
		'0067' => ['char_create'], # TODO
		'0068' => ['char_delete'], # TODO
		'0072' => ['map_login', 'a4 a4 a4 V C', [qw(accountID charID sessionID tick sex)]],
		'007D' => ['map_loaded'], # len 2
		'007E' => ['sync'], # TODO
		'0089' => ['actor_action', 'a4 C', [qw(targetID type)]],
		'008C' => ['public_chat', 'x2 Z*', [qw(message)]],
		'0096' => ['private_message', 'x2 Z24 Z*', [qw(privMsgUser privMsg)]],
		'009B' => ['actor_look_at', 'v C', [qw(head body)]],
		'009F' => ['item_take', 'a4', [qw(ID)]],
		'00B2' => ['restart', 'C', [qw(type)]],
		'00F3' => ['map_login', '', [qw()]],
		'0108' => ['party_chat', 'x2 Z*', [qw(message)]],
		'0134' => ['buy_bulk_vender', 'x2 a4 a*', [qw(venderID itemInfo)]],
		'0149' => ['alignment', 'a4 C v', [qw(targetID type point)]],
		'014D' => ['guild_check'], # len 2
		'014F' => ['guild_info_request', 'V', [qw(type)]],
		'017E' => ['guild_chat', 'x2 Z*', [qw(message)]],
		'0187' => ['ban_check', 'a4', [qw(accountID)]],
		'018A' => ['quit_request', 'v', [qw(type)]],
		'01B2' => ['shop_open'], # TODO
		'012E' => ['shop_close'], # len 2
		'0204' => ['client_hash'], # TODO
		'0208' => ['friend_response', 'a4 a4 V', [qw(friendAccountID friendCharID type)]],
		'021D' => ['less_effect'], # TODO
		'0275' => ['game_login', 'a4 a4 a4 v C x16 v', [qw(accountID sessionID sessionID2 userLevel accountSex iAccountSID)]],
		'02B0' => ['master_login', 'V Z24 a24 C H32 H26 C', [qw(version username password_rijndael master_version ip mac isGravityID)]],
		'0436' => ['map_login', 'a4 a4 a4 V C', [qw(accountID charID sessionID tick sex)]],
		'0801' => ['buy_bulk_vender', 'x2 a4 a4 a*', [qw(venderID venderCID itemInfo)]],
	);
	$self->{packet_list}{$_} = $packets{$_} for keys %packets;
	
	# # it would automatically use the first available if not set
	# my %handlers = qw(
	# 	master_login 0064
	# 	game_login 0065
	# 	map_login 0072
	# 	buy_bulk_vender 0134
	# );
	# $self->{packet_lut}{$_} = $handlers{$_} for keys %handlers;
	
	return $self;
}

sub version {
	return $masterServer->{version} || 1;
}

sub sendAddSkillPoint {
	my ($self, $skillID) = @_;
	my $msg = pack("C*", 0x12, 0x01) . pack("v*", $skillID);
	$self->sendToServer($msg);
}

sub sendAddStatusPoint {
	my ($self, $statusID) = @_;
	my $msg = pack("C*", 0xBB, 0) . pack("v*", $statusID) . pack("C*", 0x01);
	$self->sendToServer($msg);
}

sub sendAlignment {
	my ($self, $ID, $alignment) = @_;
	$self->sendToServer($self->reconstruct({
		switch => 'alignment',
		targetID => $ID,
		type => $alignment,
	}));
	debug "Sent Alignment: ".getHex($ID).", $alignment\n", "sendPacket", 2;
}

sub sendArrowCraft {
	my ($self, $index) = @_;
	my $msg = pack("C*", 0xAE, 0x01) . pack("v*", $index);
	$self->sendToServer($msg);
	debug "Sent Arrowmake: $index\n", "sendPacket", 2;
}

# 0x0089,7,actionrequest,2:6

sub sendAttackStop {
	my $self = shift;
	#my $msg = pack("C*", 0x18, 0x01);
	# Apparently this packet is wrong. The server disconnects us if we do this.
	# Sending a move command to the current position seems to be able to emulate
	# what this function is supposed to do.

	# Don't use this function, use Misc::stopAttack() instead!
	#sendMove ($char->{'pos_to'}{'x'}, $char->{'pos_to'}{'y'});
	#debug "Sent stop attack\n", "sendPacket";
}

sub sendAutoSpell {
	my ($self, $ID) = @_;
	my $msg = pack("C*", 0xce, 0x01, $ID, 0x00, 0x00, 0x00);
	$self->sendToServer($msg);
}

sub sendBanCheck {
	my ($self, $ID) = @_;
	$self->sendToServer($self->reconstruct({
		switch => 'ban_check',
		accountID => $ID,
	}));
	debug "Sent Account Ban Check Request : " . getHex($ID) . "\n", "sendPacket", 2;
}

=pod
sub sendBuy {
	my ($self, $ID, $amount) = @_;
	my $msg = pack("C*", 0xC8, 0x00, 0x08, 0x00) . pack("v*", $amount, $ID);
	$self->sendToServer($msg);
	debug "Sent buy: ".getHex($ID)."\n", "sendPacket", 2;
}
=cut
# 0x00c8,-1,npcbuylistsend,2:4
sub sendBuyBulk {
	my ($self, $r_array) = @_;
	my $msg = pack('v2', 0x00C8, 4+4*@{$r_array});
	for (my $i = 0; $i < @{$r_array}; $i++) {
		$msg .= pack('v2', $r_array->[$i]{amount}, $r_array->[$i]{itemID});
		debug "Sent bulk buy: $r_array->[$i]{itemID} x $r_array->[$i]{amount}\n", "d_sendPacket", 2;
	}
	$self->sendToServer($msg);
}

sub parse_buy_bulk_vender {
	my ($self, $args) = @_;
	@{$args->{items}} = map {{ amount => unpack('v', $_), itemIndex => unpack('x2 v', $_) }} unpack '(a4)*', $args->{itemInfo};
}

sub reconstruct_buy_bulk_vender {
	my ($self, $args) = @_;
	# ITEM index. There were any other indexes expected to be in item buying packet?
	$args->{itemInfo} = pack '(a4)*', map { pack 'v2', @{$_}{qw(amount itemIndex)} } @{$args->{items}};
}

sub sendBuyBulkVender {
	my ($self, $venderID, $r_array, $venderCID) = @_;
	$self->sendToServer($self->reconstruct({
		switch => 'buy_bulk_vender',
		venderID => $venderID,
		venderCID => $venderCID,
		items => $r_array,
	}));
	debug "Sent bulk buy vender: ".(join ', ', map {"$_->{itemIndex} x $_->{amount}"} @$r_array)."\n", "sendPacket";
}

sub sendCardMerge {
	my ($self, $card_index, $item_index) = @_;
	my $msg = pack("C*", 0x7C, 0x01) . pack("v*", $card_index, $item_index);
	$self->sendToServer($msg);
	debug "Sent Card Merge: $card_index, $item_index\n", "sendPacket";
}

sub sendCardMergeRequest {
	my ($self, $card_index) = @_;
	my $msg = pack("C*", 0x7A, 0x01) . pack("v*", $card_index);
	$self->sendToServer($msg);
	debug "Sent Card Merge Request: $card_index\n", "sendPacket";
}

sub sendCartAdd {
	my ($self, $index, $amount) = @_;
	my $msg = pack("C*", 0x26, 0x01) . pack("v*", $index) . pack("V*", $amount);
	$self->sendToServer($msg);
	debug "Sent Cart Add: $index x $amount\n", "sendPacket", 2;
}

sub sendCartGet {
	my ($self, $index, $amount) = @_;
	my $msg = pack("C*", 0x27, 0x01) . pack("v*", $index) . pack("V*", $amount);
	$self->sendToServer($msg);
	debug "Sent Cart Get: $index x $amount\n", "sendPacket", 2;
}

sub sendCharCreate {
	my ($self, $slot, $name,
	    $str, $agi, $vit, $int, $dex, $luk,
		$hair_style, $hair_color) = @_;
	$hair_color ||= 1;
	$hair_style ||= 0;

	my $msg = pack("C*", 0x67, 0x00) .
		pack("a24", stringToBytes($name)) .
		pack("C*", $str, $agi, $vit, $int, $dex, $luk, $slot) .
		pack("v*", $hair_color, $hair_style);
	$self->sendToServer($msg);
}

sub sendCharDelete {
	my ($self, $charID, $email) = @_;
	my $msg = pack("C*", 0x68, 0x00) .
			$charID . pack("a40", stringToBytes($email));
	$self->sendToServer($msg);
}

sub sendChatRoomBestow {
	my ($self, $name) = @_;

	my $binName = stringToBytes($name);
	$binName = substr($binName, 0, 24) if (length($binName) > 24);
	$binName .= chr(0) x (24 - length($binName));

	my $msg = pack("C*", 0xE0, 0x00, 0x00, 0x00, 0x00, 0x00) . $binName;
	$self->sendToServer($msg);
	debug "Sent Chat Room Bestow: $name\n", "sendPacket", 2;
}

sub sendChatRoomChange {
	my ($self, $title, $limit, $public, $password) = @_;

	my $titleBytes = stringToBytes($title);
	my $passwordBytes = stringToBytes($password);
	$passwordBytes = substr($passwordBytes, 0, 8) if (length($passwordBytes) > 8);
	$passwordBytes = $passwordBytes . chr(0) x (8 - length($passwordBytes));

	my $msg = pack("C*", 0xDE, 0x00).pack("v*", length($titleBytes) + 15, $limit).pack("C*",$public).$passwordBytes.$titleBytes;
	$self->sendToServer($msg);
	debug "Sent Change Chat Room: $title, $limit, $public, $password\n", "sendPacket", 2;
}

sub sendChatRoomCreate {
	my ($self, $title, $limit, $public, $password) = @_;

	my $passwordBytes = stringToBytes($password);
	$passwordBytes = substr($passwordBytes, 0, 8) if (length($passwordBytes) > 8);
	$passwordBytes = $passwordBytes . chr(0) x (8 - length($passwordBytes));
	my $binTitle = stringToBytes($title);

	my $msg = pack("C*", 0xD5, 0x00) .
		pack("v*", length($binTitle) + 15, $limit) .
		pack("C*", $public) . $passwordBytes . $binTitle;
	$self->sendToServer($msg);
	debug "Sent Create Chat Room: $title, $limit, $public, $password\n", "sendPacket", 2;
}

sub sendChatRoomJoin {
	my ($self, $ID, $password) = @_;

	my $passwordBytes = stringToBytes($password);
	$passwordBytes = substr($passwordBytes, 0, 8) if (length($passwordBytes) > 8);
	$passwordBytes = $passwordBytes . chr(0) x (8 - length($passwordBytes));
	my $msg = pack("C*", 0xD9, 0x00).$ID.$passwordBytes;
	$self->sendToServer($msg);
	debug "Sent Join Chat Room: ".getHex($ID)." $password\n", "sendPacket", 2;
}

sub sendChatRoomKick {
	my ($self, $name) = @_;

	my $binName = stringToBytes($name);
	$binName = substr($binName, 0, 24) if (length($binName) > 24);
	$binName .= chr(0) x (24 - length($binName));
	my $msg = pack("C*", 0xE2, 0x00) . $binName;
	$self->sendToServer($msg);
	debug "Sent Chat Room Kick: $name\n", "sendPacket", 2;
}

sub sendChatRoomLeave {
	my $self = shift;
	my $msg = pack("C*", 0xE3, 0x00);
	$self->sendToServer($msg);
	debug "Sent Leave Chat Room\n", "sendPacket", 2;
}

# 0x022d,5,hommenu,4
sub sendHomunculusCommand {
	my ($self, $command, $type) = @_; # $type is ignored, $command can be 0:get stats, 1:feed or 2:fire
	my $msg = pack ('v2 C', 0x022D, $type, $command);
	$self->sendToServer($msg);
	debug "Sent Homunculus Command $command", "sendPacket", 2;
}

sub sendCompanionRelease {
	my $msg = pack("C*", 0x2A, 0x01);
	$_[0]->sendToServer($msg);
	debug "Sent Companion Release (Cart, Falcon or Pecopeco)\n", "sendPacket", 2;
}

sub sendCurrentDealCancel {
	my $msg = pack("C*", 0xED, 0x00);
	$_[0]->sendToServer($msg);
	debug "Sent Cancel Current Deal\n", "sendPacket", 2;
}

sub sendDeal {
	my ($self, $ID) = @_;
	my $msg = pack("C*", 0xE4, 0x00) . $ID;
	$_[0]->sendToServer($msg);
	debug "Sent Initiate Deal: ".getHex($ID)."\n", "sendPacket", 2;
}

sub sendDealReply {
	#Reply to a trade-request.
	# Type values:
	# 0: Char is too far
	# 1: Character does not exist
	# 2: Trade failed
	# 3: Accept
	# 4: Cancel
	# Weird enough, the client should only send 3/4
	# and the server is the one that can reply 0~2
	my ($self, $action) = @_;
	my $msg = pack('v C', 0x00E6, $action);
	$_[0]->sendToServer($msg);
	debug "Sent " . ($action == 3 ? "Accept": ($action == 4 ? "Cancel" : "action: " . $action)) . " Deal\n", "sendPacket", 2;
}

# TODO: legacy plugin support, remove later
sub sendDealAccept {
	$_[0]->sendDealReply(3);
	debug "Sent Cancel Deal\n", "sendPacket", 2;
}

# TODO: legacy plugin support, remove later
sub sendDealCancel {
	$_[0]->sendDealReply(4);
	debug "Sent Cancel Deal\n", "sendPacket", 2;
}

sub sendDealAddItem {
	my ($self, $index, $amount) = @_;
	my $msg = pack("C*", 0xE8, 0x00) . pack("v*", $index) . pack("V*",$amount);
	$_[0]->sendToServer($msg);
	debug "Sent Deal Add Item: $index, $amount\n", "sendPacket", 2;
}

sub sendDealFinalize {
	my $msg = pack("C*", 0xEB, 0x00);
	$_[0]->sendToServer($msg);
	debug "Sent Deal OK\n", "sendPacket", 2;
}

sub sendDealOK {
	my $msg = pack("C*", 0xEB, 0x00);
	$_[0]->sendToServer($msg);
	debug "Sent Deal OK\n", "sendPacket", 2;
}

sub sendDealTrade {
	my $msg = pack("C*", 0xEF, 0x00);
	$_[0]->sendToServer($msg);
	debug "Sent Deal Trade\n", "sendPacket", 2;
}

sub sendDrop {
	my ($self, $index, $amount) = @_;
	my $msg;

	$msg = pack("C*", 0xA2, 0x00) . pack("v*", $index, $amount);

	$self->sendToServer($msg);
	debug "Sent drop: $index x $amount\n", "sendPacket", 2;
}

sub sendEmotion {
	my ($self, $ID) = @_;
	my $msg = pack("C*", 0xBF, 0x00).pack("C1",$ID);
	$self->sendToServer($msg);
	debug "Sent Emotion\n", "sendPacket", 2;
}

sub sendEnteringVender {
	my ($self, $ID) = @_;
	my $msg = pack("C*", 0x30, 0x01) . $ID;
	$self->sendToServer($msg);
	debug "Sent Entering Vender: ".getHex($ID)."\n", "sendPacket", 2;
}

sub sendEquip {
	my ($self, $index, $type) = @_;
	my $msg = pack("C*", 0xA9, 0x00) . pack("v*", $index) .  pack("v*", $type);
	$self->sendToServer($msg);
	debug "Sent Equip: $index Type: $type\n" , 2;
}

# 0x0208,11,friendslistreply,2:6:10
# Reject:0/Accept:1

sub sendFriendRequest {
	my ($self, $name) = @_;

	my $binName = stringToBytes($name);
	$binName = substr($binName, 0, 24) if (length($binName) > 24);
	$binName = $binName . chr(0) x (24 - length($binName));
	my $msg = pack("C*", 0x02, 0x02) . $binName;

	$self->sendToServer($msg);
	debug "Sent Request to be a friend: $name\n", "sendPacket";
}

sub sendFriendRemove {
	my ($self, $accountID, $charID) = @_;
	my $msg = pack("C*", 0x03, 0x02) . $accountID . $charID;
	$self->sendToServer($msg);
	debug "Sent Remove a friend\n", "sendPacket";
}

sub sendProduceMix {
	my ($self, $ID,
		# nameIDs for added items such as Star Crumb or Flame Heart
		$item1, $item2, $item3) = @_;

	my $msg = pack("v5", 0x018E, $ID, $item1, $item2, $item3);
	$self->sendToServer($msg);
	debug "Sent Forge, Produce Item: $ID\n" , 2;
}

sub sendGetCharacterName {
	my ($self, $ID) = @_;
	my $msg = pack("C*", 0x93, 0x01) . $ID;
	$self->sendToServer($msg);
	debug "Sent get character name: ID - ".getHex($ID)."\n", "sendPacket", 2;
}

sub sendGetPlayerInfo {
	my ($self, $ID) = @_;
	my $msg;
	$msg = pack("C*", 0x94, 0x00) . $ID;
	$self->sendToServer($msg);
	debug "Sent get player info: ID - ".getHex($ID)."\n", "sendPacket", 2;
}

sub sendNPCBuySellList { # type:0 get store list, type:1 get sell list
	my ($self, $ID, $type) = @_;
	my $msg = pack('v a4 C', 0x00C5, $ID , $type);
	$self->sendToServer($msg);
	debug "Sent get ".($type ? "buy" : "sell")." list to NPC: ".getHex($ID)."\n", "sendPacket", 2;
}

=pod
sub sendGetStoreList {
	my ($self, $ID, $type) = @_;
	my $msg = pack("C*", 0xC5, 0x00) . $ID . pack("C*",0x00);
	$self->sendToServer($msg);
	debug "Sent get store list: ".getHex($ID)."\n", "sendPacket", 2;
}

sub sendGetSellList {
	my ($self, $ID) = @_;
	my $msg = pack("C*", 0xC5, 0x00) . $ID . pack("C*",0x01);
	$self->sendToServer($msg);
	debug "Sent sell to NPC: ".getHex($ID)."\n", "sendPacket", 2;
}
=cut

sub sendGMSummon {
	my ($self, $playerName) = @_;
	my $packet = pack("C*", 0xBD, 0x01) . pack("a24", stringToBytes($playerName));
	$self->sendToServer($packet);
}

sub sendGuildAlly {
	my ($self, $ID, $flag) = @_;
	my $msg = pack("C*", 0x72, 0x01).$ID.pack("V1", $flag);
	$self->sendToServer($msg);
	debug "Sent Ally Guild : ".getHex($ID).", $flag\n", "sendPacket", 2;
}

sub sendGuildBreak {
	my ($self, $guildName) = @_;
	my $msg = pack("C C a40", 0x5D, 0x01, stringToBytes($guildName));
	$self->sendToServer($msg);
	debug "Sent Guild Break: $guildName\n", "sendPacket", 2;
}

sub sendGuildCreate {
	my ($self, $name) = @_;
	# By Default, the second param is our CharID. which indicate the Guild Master Char ID
	my $msg = pack('v a4 a24', 0x0165, $charID, stringToBytes($name));
	$self->sendToServer($msg);
	debug "Sent Guild Create: $name\n", "sendPacket", 2;
}

sub sendGuildJoin {
	my ($self, $ID, $flag) = @_;
	my $msg = pack("C*", 0x6B, 0x01).$ID.pack("V1", $flag);
	$self->sendToServer($msg);
	debug "Sent Join Guild : ".getHex($ID).", $flag\n", "sendPacket";
}

sub sendGuildJoinRequest {
	my ($self, $ID) = @_;
	my $msg = pack("C*", 0x68, 0x01).$ID.$accountID.$charID;
	$self->sendToServer($msg);
	debug "Sent Request Join Guild: ".getHex($ID)."\n", "sendPacket";
}

sub sendGuildLeave {
	my ($self, $reason) = @_;
	my $mess = pack("Z40", stringToBytes($reason));
	my $msg = pack("C*", 0x59, 0x01).$guild{ID}.$accountID.$charID.$mess;
	$self->sendToServer($msg);
	debug "Sent Guild Leave: $reason (".getHex($msg).")\n", "sendPacket";
}

sub sendGuildMemberKick {
	my ($self, $guildID, $accountID, $charID, $cause) = @_;
	my $msg = pack("C*", 0x5B, 0x01).$guildID.$accountID.$charID.pack("a40", stringToBytes($cause));
	$self->sendToServer($msg);
	debug "Sent Guild Kick: ".getHex($charID)."\n", "sendPacket";
}

=pod
sub sendGuildMemberTitleSelect {
	# set the title for a member
	my ($self, $accountID, $charID, $index) = @_;

	my $msg = pack("C*", 0x55, 0x01).pack("v1",16).$accountID.$charID.pack("V1",$index);
	$self->sendToServer($msg);
	debug "Sent Change Guild title: ".getHex($charID)." $index\n", "sendPacket", 2;
}
=cut
# 0x0155,-1,guildchangememberposition,2
sub sendGuildMemberPositions {
	my ($self, $r_array) = @_;
	my $msg = pack('v2', 0x0155, 4+12*@{$r_array});
	for (my $i = 0; $i < @{$r_array}; $i++) {
		$msg .= pack('a4 a4 V', $r_array->[$i]{accountID}, $r_array->[$i]{charID}, $r_array->[$i]{index});
		debug "Sent GuildChangeMemberPositions: $r_array->[$i]{accountID} $r_array->[$i]{charID} $r_array->[$i]{index}\n", "d_sendPacket", 2;
	}
	$self->sendToServer($msg);
}

sub sendGuildNotice {
	# sets the notice/announcement for the guild
	my ($self, $guildID, $name, $notice) = @_;
	my $msg = pack("C*", 0x6E, 0x01) . $guildID .
		pack("a60 a120", stringToBytes($name), stringToBytes($notice));
	$self->sendToServer($msg);
	debug "Sent Change Guild Notice: $notice\n", "sendPacket", 2;
}

=pod
sub sendGuildRankChange {
	# change the title for a certain index
	# i would  guess 0 is the top rank, but i dont know
	my ($self, $index, $permissions, $tax, $title) = @_;

	my $msg = pack("C*", 0x61, 0x01) .
		pack("v1", 44) . # packet length, we can actually send multiple titles in the same packet if we wanted to
		pack("V1", $index) . # index of this rank in the list
		pack("V1", $permissions) . # this is their abilities, not sure what format
		pack("V1", $index) . # isnt even used on emulators, but leave in case Aegis wants this
		pack("V1", $tax) . # guild tax amount, not sure what format
		pack("a24", $title);
	$self->sendToServer($msg);
	debug "Sent Set Guild title: $index $title\n", "sendPacket", 2;
}
=cut
# 0x0161,-1,guildchangepositioninfo,2
sub sendGuildPositionInfo {
	my ($self, $r_array) = @_;
	my $msg = pack('v2', 0x0161, 4+44*@{$r_array});
	for (my $i = 0; $i < @{$r_array}; $i++) {
		$msg .= pack('v2 V4 a24', $r_array->[$i]{index}, $r_array->[$i]{permissions}, $r_array->[$i]{index}, $r_array->[$i]{tax}, stringToBytes($r_array->[$i]{title}));
		debug "Sent GuildPositionInfo: $r_array->[$i]{index}, $r_array->[$i]{permissions}, $r_array->[$i]{index}, $r_array->[$i]{tax}, ".stringToBytes($r_array->[$i]{title})."\n", "d_sendPacket", 2;
	}
	$self->sendToServer($msg);
}

sub sendGuildRequestEmblem {
	my ($self, $guildID) = @_;
	my $msg = pack("v V", 0x0151, $guildID);
	$self->sendToServer($msg);
	debug "Sent Guild Request Emblem.\n", "sendPacket";
}

sub sendGuildSetAlly {
	# this packet is for guildmaster asking to set alliance with another guildmaster
	# the other sub for sendGuildAlly are responses to this sub
	# kept the parameters open, but everything except $targetAID could be replaced with Global variables
	# unless you plan to mess around with the alliance packet, no exploits though, I tried ;-)
	# -zdivpsa
	my ($self, $targetAID, $myAID, $charID) = @_;	# remote socket, $net
	my $msg =	pack("C*", 0x70, 0x01) .
			$targetAID .
			$myAID .
			$charID;
	$self->sendToServer($msg);

}

sub sendHomunculusMove {
	my ($self, $homunID, $x, $y) = @_;
	my $msg = pack("C*", 0x32, 0x02) . $homunID . getCoordString(int $x, int $y);
	$self->sendToServer($msg);
	debug "Sent Homunculus move to: $x, $y\n", "sendPacket", 2;
}

sub sendHomunculusAttack {
	my $self = shift;
	my $homunID = shift;
	my $targetID = shift;
	my $flag = shift;
	my $msg = pack("C*", 0x33, 0x02) . $homunID . $targetID . pack("C1", $flag);
	$self->sendToServer($msg);
	debug "Sent Homunculus attack: ".getHex($targetID)."\n", "sendPacket", 2;
}

sub sendHomunculusStandBy {
	my $self = shift;
	my $homunID = shift;
	my $msg = pack("C*", 0x34, 0x02) . $homunID;
	$self->sendToServer($msg);
	debug "Sent Homunculus standby\n", "sendPacket", 2;
}

sub sendHomunculusName {
	my $self = shift;
	my $name = shift;
	my $msg = pack("v1 a24", 0x0231, stringToBytes($name));
	$self->sendToServer($msg);
	debug "Sent Homunculus Rename: $name\n", "sendPacket", 2;
}

sub sendIdentify {
	my $self = shift;
	my $index = shift;
	my $msg = pack("C*", 0x78, 0x01) . pack("v*", $index);
	$self->sendToServer($msg);
	debug "Sent Identify: $index\n", "sendPacket", 2;
}

sub sendIgnore {
	my $self = shift;
	my $name = shift;
	my $flag = shift;

	my $binName = stringToBytes($name);
	$binName = substr($binName, 0, 24) if (length($binName) > 24);
	$binName = $binName . chr(0) x (24 - length($binName));
	my $msg = pack("C*", 0xCF, 0x00) . $binName . pack("C*", $flag);

	$self->sendToServer($msg);
	debug "Sent Ignore: $name, $flag\n", "sendPacket", 2;
}

sub sendIgnoreAll {
	my $self = shift;
	my $flag = shift;
	my $msg = pack("C*", 0xD0, 0x00).pack("C*", $flag);
	$self->sendToServer($msg);
	debug "Sent Ignore All: $flag\n", "sendPacket", 2;
}

sub sendIgnoreListGet {
	my $self = shift;
	my $flag = shift;
	my $msg = pack("C*", 0xD3, 0x00);
	$self->sendToServer($msg);
	debug "Sent get Ignore List: $flag\n", "sendPacket", 2;
}

sub sendItemUse {
	my ($self, $ID, $targetID) = @_;
	my $msg;
	
	$msg = pack("C*", 0xA7, 0x00).pack("v*",$ID) .
		$targetID;

	$self->sendToServer($msg);
	debug "Item Use: $ID\n", "sendPacket", 2;
}

sub sendMasterCodeRequest {
	my $self = shift;
	my $type = shift;
	my $code = shift;
	my $msg;

	if ($type eq 'code') {
		$msg = '';
		foreach (split(/ /, $code)) {
			$msg .= pack("C1",hex($_));
		}

	} else { # type eq 'type'
		if ($code == 1) {
			$msg = pack("C*", 0x04, 0x02, 0x7B, 0x8A, 0xA8, 0x90, 0x2F, 0xD8, 0xE8, 0x30, 0xF8, 0xA5, 0x25, 0x7A, 0x0D, 0x3B, 0xCE, 0x52);
		} elsif ($code == 2) {
			$msg = pack("C*", 0x04, 0x02, 0x27, 0x6A, 0x2C, 0xCE, 0xAF, 0x88, 0x01, 0x87, 0xCB, 0xB1, 0xFC, 0xD5, 0x90, 0xC4, 0xED, 0xD2);
		} elsif ($code == 3) {
			$msg = pack("C*", 0x04, 0x02, 0x42, 0x00, 0xB0, 0xCA, 0x10, 0x49, 0x3D, 0x89, 0x49, 0x42, 0x82, 0x57, 0xB1, 0x68, 0x5B, 0x85);
		} elsif ($code == 4) {
			$msg = pack("C*", 0x04, 0x02, 0x22, 0x37, 0xD7, 0xFC, 0x8E, 0x9B, 0x05, 0x79, 0x60, 0xAE, 0x02, 0x33, 0x6D, 0x0D, 0x82, 0xC6);
		} elsif ($code == 5) {
			$msg = pack("C*", 0x04, 0x02, 0xc7, 0x0A, 0x94, 0xC2, 0x7A, 0xCC, 0x38, 0x9A, 0x47, 0xF5, 0x54, 0x39, 0x7C, 0xA4, 0xD0, 0x39);
		}
	}
	$msg .= pack("C*", 0xDB, 0x01);
	$self->sendToServer($msg);
}

sub sendMasterSecureLogin {
	my $self = shift;
	my $username = shift;
	my $password = shift;
	my $salt = shift;
	my $version = shift;
	my $master_version = shift;
	my $type =  shift;
	my $account = shift;
	my $md5 = Digest::MD5->new;
	my ($msg);

	$username = stringToBytes($username);
	$password = stringToBytes($password);
	if ($type % 2 == 1) {
		$salt = $salt . $password;
	} else {
		$salt = $password . $salt;
	}
	$md5->add($salt);
	if ($type < 3 ) {
		$msg = pack("C*", 0xDD, 0x01) . pack("V1", $version) . pack("a24", $username) .
					 $md5->digest . pack("C*", $master_version);
	}else{
		$account = ($account>0) ? $account -1 : 0;
		$msg = pack("C*", 0xFA, 0x01) . pack("V1", $version) . pack("a24", $username) .
					 $md5->digest . pack("C*", $master_version). pack("C1", $account);
	}
	$self->sendToServer($msg);
}

sub sendMemo {
	my $self = shift;
	my $msg = pack("C*", 0x1D, 0x01);
	$self->sendToServer($msg);
	debug "Sent Memo\n", "sendPacket", 2;
}

sub sendMove {
	my ($self, $x, $y) = @_;
	my $msg = pack("C*", 0x85, 0x00) . getCoordString(int $x, int $y);
	$self->sendToServer($msg);
	debug "Sent move to: $x, $y\n", "sendPacket", 2;
}

sub sendOpenShop {
	my ($self, $title, $items) = @_;

	my $length = 0x55 + 0x08 * @{$items};
	my $msg = pack("C*", 0xB2, 0x01).
		pack("v*", $length).
		pack("a80", stringToBytes($title)).
		pack("C*", 0x01);

	foreach my $item (@{$items}) {
		$msg .= pack("v1", $item->{index}).
			pack("v1", $item->{amount}).
			pack("V1", $item->{price});
	}

	$self->sendToServer($msg);
}

sub sendPartyJoin {
	my $self = shift;
	my $ID = shift;
	my $flag = shift;
	my $msg = pack("C*", 0xFF, 0x00).$ID.pack("V", $flag);
	$self->sendToServer($msg);
	debug "Sent Join Party: ".getHex($ID).", $flag\n", "sendPacket", 2;
}

sub sendPartyJoinRequest {
	my $self = shift;
	my $ID = shift;
	my $msg = pack("C*", 0xFC, 0x00).$ID;
	$self->sendToServer($msg);
	debug "Sent Request Join Party: ".getHex($ID)."\n", "sendPacket", 2;
}

sub sendPartyLeader {
	my $self = shift;
	my $ID = shift;
	my $msg = pack("C*", 0xDA, 0x07).$ID;
	$self->sendToServer($msg);
	debug "Sent Change Party Leader ".getHex($ID)."\n", "sendPacket", 2;
}

sub _binName {
	my $name = shift;
	
	$name = stringToBytes ($name);
	$name = substr ($name, 0, 24) if 24 < length $name;
	$name .= "\x00" x (24 - length $name);
	return $name;
}

sub sendPartyJoinRequestByName {
	my $self = shift;
	my $name = shift;
	my $msg = pack ('C*', 0xc4, 0x02) . _binName ($name);
	$self->sendToServer($msg);
	debug "Sent Request Join Party (by name): $name\n", "sendPacket", 2;
}

sub sendPartyJoinRequestByNameReply {
	my ($self, $accountID, $flag) = @_;
	my $msg = pack('v a4 C', 0x02C7, $accountID, $flag);
	$self->sendToServer($msg);
	debug "Sent reply Party Invite.\n", "sendPacket", 2;
}

sub sendPartyKick {
	my $self = shift;
	my $ID = shift;
	my $name = shift;
	my $msg = pack("C*", 0x03, 0x01) . $ID . _binName ($name);
	$self->sendToServer($msg);
	debug "Sent Kick Party: ".getHex($ID).", $name\n", "sendPacket", 2;
}

sub sendPartyLeave {
	my $self = shift;
	my $msg = pack("C*", 0x00, 0x01);
	$self->sendToServer($msg);
	debug "Sent Leave Party\n", "sendPacket", 2;
}

sub sendPartyOrganize {
	my $self = shift;
	my $name = shift;
	my $share1 = shift || 1;
	my $share2 = shift || 1;

	my $binName = stringToBytes($name);
	$binName = substr($binName, 0, 24) if (length($binName) > 24);
	$binName .= chr(0) x (24 - length($binName));
	#my $msg = pack("C*", 0xF9, 0x00) . $binName;
	# I think this is obsolete - which serverTypes still support this packet anyway?
	# FIXME: what are shared with $share1 and $share2? experience? item? vice-versa?
	
	my $msg = pack("C*", 0xE8, 0x01) . $binName . pack("C*", $share1, $share2);

	$self->sendToServer($msg);
	debug "Sent Organize Party: $name\n", "sendPacket", 2;
}

# legacy plugin support, remove later
sub sendPartyShareEXP {
	my ($self, $exp) = @_;
	$self->sendPartyOption($exp, 0);
}

# 0x0102,6,partychangeoption,2:4
# note: item share changing seems disabled in newest clients
sub sendPartyOption {
	my ($self, $exp, $item) = @_;
	my $msg = pack('v3', 0x0102, $exp, $item);
	$self->sendToServer($msg);
	debug "Sent Party 0ption\n", "sendPacket", 2;
}

sub sendPetCapture {
	my ($self, $monID) = @_;
	my $msg = pack('v a4', 0x019F, $monID);
	$self->sendToServer($msg);
	debug "Sent pet capture: ".getHex($monID)."\n", "sendPacket", 2;
}

# 0x01a1,3,petmenu,2
sub sendPetMenu {
	my ($self, $type) = @_; # 0:info, 1:feed, 2:performance, 3:to egg, 4:uneq item
	my $msg = pack('v C', 0x01A1, $type);
	$self->sendToServer($msg);
	debug "Sent Pet Menu\n", "sendPacket", 2;
}

sub sendPetHatch {
	my ($self, $index) = @_;
	my $msg = pack('v2', 0x01A7, $index);
	$self->sendToServer($msg);
	debug "Sent Incubator hatch: $index\n", "sendPacket", 2;
}

sub sendPetName {
	my ($self, $name) = @_;
	my $msg = pack('v a24', 0x01A5, stringToBytes($name));
	$self->sendToServer($msg);
	debug "Sent Pet Rename: $name\n", "sendPacket", 2;
}

# 0x01af,4,changecart,2
sub sendChangeCart { # lvl: 1, 2, 3, 4, 5
	my ($self, $lvl) = @_;
	my $msg = pack('v2', 0x01AF, $lvl);
	$self->sendToServer($msg);
	debug "Sent Cart Change to : $lvl\n", "sendPacket", 2;
}

sub sendPreLoginCode {
	# no server actually needs this, but we might need it in the future?
	my $self = shift;
	my $type = shift;
	my $msg;
	if ($type == 1) {
		$msg = pack("C*", 0x04, 0x02, 0x82, 0xD1, 0x2C, 0x91, 0x4F, 0x5A, 0xD4, 0x8F, 0xD9, 0x6F, 0xCF, 0x7E, 0xF4, 0xCC, 0x49, 0x2D);
	}
	$self->sendToServer($msg);
	debug "Sent pre-login packet $type\n", "sendPacket", 2;
}

sub sendRaw {
	my $self = shift;
	my $raw = shift;
	my @raw;
	my $msg;
	@raw = split / /, $raw;
	foreach (@raw) {
		$msg .= pack("C", hex($_));
	}
	$self->sendToServer($msg);
	debug "Sent Raw Packet: @raw\n", "sendPacket", 2;
}

sub sendRequestMakingHomunculus {
	# WARNING: If you don't really know, what are you doing - don't touch this
	my ($self, $make_homun) = @_;
	
	my $skill = new Skill (idn => 241);
	
	if (
		Actor::Item::get (997) && Actor::Item::get (998) && Actor::Item::get (999)
		&& ($char->getSkillLevel ($skill) > 0)
	) {
		my $msg = pack ('v C', 0x01CA, $make_homun);
		$self->sendToServer($msg);
		debug "Sent RequestMakingHomunculus\n", "sendPacket", 2;
	}
}

sub sendRemoveAttachments {
	# remove peco, falcon, cart
	my $msg = pack("C*", 0x2A, 0x01);
	$_[0]->sendToServer($msg);
	debug "Sent remove attachments\n", "sendPacket", 2;
}

sub sendRepairItem {
	my ($self, $args) = @_;
	my $msg = pack("C2 v2 V2 C1", 0xFD, 0x01, $args->{index}, $args->{nameID}, $args->{status}, $args->{status2}, $args->{listID});
	$self->sendToServer($msg);
	debug ("Sent repair item: ".$args->{index}."\n", "sendPacket", 2);
}

sub sendSell {
	my $self = shift;
	my $index = shift;
	my $amount = shift;
	my $msg = pack("C*", 0xC9, 0x00, 0x08, 0x00) . pack("v*", $index, $amount);
	$self->sendToServer($msg);
	debug "Sent sell: $index x $amount\n", "sendPacket", 2;
}

sub sendSellBulk {
	my $self = shift;
	my $r_array = shift;
	my $sellMsg = "";

	for (my $i = 0; $i < @{$r_array}; $i++) {
		$sellMsg .= pack("v*", $r_array->[$i]{index}, $r_array->[$i]{amount});
		debug "Sent bulk sell: $r_array->[$i]{index} x $r_array->[$i]{amount}\n", "d_sendPacket", 2;
	}

	my $msg = pack("C*", 0xC9, 0x00) . pack("v*", length($sellMsg) + 4) . $sellMsg;
	$self->sendToServer($msg);
}

sub sendSkillUse {
	my ($self, $ID, $lv, $targetID) = @_;
	my $msg;

	$msg = pack("C*", 0x13, 0x01).pack("v*",$lv,$ID).$targetID;

	$self->sendToServer($msg);
	debug "Skill Use: $ID\n", "sendPacket", 2;
}

sub sendSkillUseLoc {
	my ($self, $ID, $lv, $x, $y) = @_;
	my $msg;

	$msg = pack("C*", 0x16, 0x01).pack("v*",$lv,$ID,$x,$y);
	
	$self->sendToServer($msg);
	debug "Skill Use on Location: $ID, ($x, $y)\n", "sendPacket", 2;
}

sub sendStorageAdd {
	my ($self, $index, $amount) = @_;
	my $msg;

	$msg = pack("C*", 0xF3, 0x00) . pack("v*", $index) . pack("V*", $amount);

	$self->sendToServer($msg);
	debug "Sent Storage Add: $index x $amount\n", "sendPacket", 2;
}

sub sendStorageAddFromCart {
	my $self = shift;
	my $index = shift;
	my $amount = shift;
	my $msg;
	$msg = pack("C*", 0x29, 0x01) . pack("v*", $index) . pack("V*", $amount);
	$self->sendToServer($msg);
	debug "Sent Storage Add From Cart: $index x $amount\n", "sendPacket", 2;
}

sub sendStorageClose {
	my ($self) = @_;
	my $msg;
	if (($self->{serverType} == 3) || ($self->{serverType} == 5) || ($self->{serverType} == 9) || ($self->{serverType} == 15)) {
		$msg = pack("C*", 0x93, 0x01);
	} elsif ($self->{serverType} == 12) {
		$msg = pack("C*", 0x72, 0x00);
	} elsif ($self->{serverType} == 14) {
		$msg = pack("C*", 0x16, 0x01);
	} else {
		$msg = pack("C*", 0xF7, 0x00);
	}

	$self->sendToServer($msg);
	debug "Sent Storage Done\n", "sendPacket", 2;
}

sub sendStorageGet {
	my ($self, $index, $amount) = @_;
	my $msg;

	$msg = pack("C*", 0xF5, 0x00) . pack("v*", $index) . pack("V*", $amount);
	
	$self->sendToServer($msg);
	debug "Sent Storage Get: $index x $amount\n", "sendPacket", 2;
}

sub sendStorageGetToCart {
	my $self = shift;
	my $index = shift;
	my $amount = shift;
	my $msg;
	$msg = pack("C*", 0x28, 0x01) . pack("v*", $index) . pack("V*", $amount);
	$self->sendToServer($msg);
	debug "Sent Storage Get From Cart: $index x $amount\n", "sendPacket", 2;
}

sub sendStoragePassword {
	my $self = shift;
	# 16 byte packed hex data
	my $pass = shift;
	# 2 = set password ?
	# 3 = give password ?
	my $type = shift;
	my $msg;
	if ($type == 3) {
		$msg = pack("C C v", 0x3B, 0x02, $type).$pass.pack("H*", "EC62E539BB6BBC811A60C06FACCB7EC8");
	} elsif ($type == 2) {
		$msg = pack("C C v", 0x3B, 0x02, $type).pack("H*", "EC62E539BB6BBC811A60C06FACCB7EC8").$pass;
	} else {
		ArgumentException->throw("The 'type' argument has invalid value ($type).");
	}
	$self->sendToServer($msg);
}

sub sendLoginPinCode {
	my $self = shift;
	# String's with PIN codes
	my $pin1 = shift;
	my $pin2 = shift;
        # Actually the Key
	my $key_v = shift;
	# 2 = set password
	# 3 = enter password
	my $type = shift;
	my $encryptionKey = shift;

	my $msg;
	if ($pin1 !~ /^\d*$/) {
		ArgumentException->throw("PIN code 1 must contain only digits.");
	}
	if ($type == 2 && $pin2 !~ /^\d*$/) {
		ArgumentException->throw("PIN code 2 must contain only digits.");
	}
	if (!$encryptionKey) {
		ArgumentException->throw("No encryption key given.");
	}

	my $crypton = new Utils::Crypton(pack("V*", @{$encryptionKey}), 32);
	my $num1 = pin_encode($pin1, $key_v);
	my $num2 = pin_encode($pin2, $key_v);
	if ($type == 2) {
		if ((length($pin1) > 3) && (length($pin1) < 9) && (length($pin2) > 3) && (length($pin2) < 9)) {
			my $ciphertextblock1 = $crypton->encrypt(pack("V*", $num1, 0, 0, 0)); 
			my $ciphertextblock2 = $crypton->encrypt(pack("V*", $num2, 0, 0, 0));
			$msg = pack("C C v", 0x3B, 0x02, $type).$ciphertextblock1.$ciphertextblock2;
			$self->sendToServer($msg);
		} else {
			ArgumentException->throw("Both PIN codes must be more than 3 and less than 9 characters long.");
		}
	} elsif ($type == 3) {
		if ((length($pin1) > 3) && (length($pin1) < 9)) {
			my $ciphertextblock1 = $crypton->encrypt(pack("V*", $num1, 0, 0, 0)); 
			my $ciphertextblock2 = $crypton->encrypt(pack("V*", 0, 0, 0, 0)); 
			$msg = pack("C C v", 0x3B, 0x02, $type).$ciphertextblock1.$ciphertextblock2;
			$self->sendToServer($msg);
		} else {
			ArgumentException->throw("PIN code 1 must be more than 3 and less than 9 characters long.");
		}
	} else {
		ArgumentException->throw("The 'type' argument has invalid value ($type).");
	}
}

sub sendSkillSelect {
	my ($self, $skillID, $why) = @_;
	$_[0]->sendToServer(pack 'C2 V v', 0x43, 0x04, $why, $skillID);
	debug sprintf("Sent Skill Select (skillID: %d, why: %d)", $skillID, $why), 'sendPacket', 2;
}

sub sendSuperNoviceDoriDori {
	my $msg = pack("C*", 0xE7, 0x01);
	$_[0]->sendToServer($msg);
	debug "Sent Super Novice dori dori\n", "sendPacket", 2;
}

# TODO: is this the sn mental ingame triggered trough the poem?
sub sendSuperNoviceExplosion {
	my $msg = pack("C*", 0xED, 0x01);
	$_[0]->sendToServer($msg);
	debug "Sent Super Novice Explosion\n", "sendPacket", 2;
}

sub sendSync {
	my ($self, $initialSync) = @_;
	my $msg;
	# XKore mode 1 lets the client take care of syncing.
	return if ($self->{net}->version == 1);
	
	$syncSync = pack("V", getTickCount());
	$msg = pack("C*", 0x7E, 0x00) . $syncSync;

	$self->sendToServer($msg);
	debug "Sent Sync\n", "sendPacket", 2;
}

sub sendTalk {
	my $self = shift;
	my $ID = shift;
	my $msg = pack("C*", 0x90, 0x00) . $ID . pack("C*",0x01);
	$self->sendToServer($msg);
	debug "Sent talk: ".getHex($ID)."\n", "sendPacket", 2;
}

sub sendTalkCancel {
	my $self = shift;
	my $ID = shift;
	my $msg = pack("C*", 0x46, 0x01) . $ID;
	$self->sendToServer($msg);
	debug "Sent talk cancel: ".getHex($ID)."\n", "sendPacket", 2;
}

sub sendTalkContinue {
	my $self = shift;
	my $ID = shift;
	my $msg = pack("C*", 0xB9, 0x00) . $ID;
	$self->sendToServer($msg);
	debug "Sent talk continue: ".getHex($ID)."\n", "sendPacket", 2;
}

sub sendTalkResponse {
	my $self = shift;
	my $ID = shift;
	my $response = shift;
	my $msg = pack("C*", 0xB8, 0x00) . $ID. pack("C1",$response);
	$self->sendToServer($msg);
	debug "Sent talk respond: ".getHex($ID).", $response\n", "sendPacket", 2;
}

sub sendTalkNumber {
	my $self = shift;
	my $ID = shift;
	my $number = shift;
	my $msg = pack("C*", 0x43, 0x01) . $ID .
			pack("V1", $number);
	$self->sendToServer($msg);
	debug "Sent talk number: ".getHex($ID).", $number\n", "sendPacket", 2;
}

sub sendTalkText {
	my $self = shift;
	my $ID = shift;
	my $input = stringToBytes(shift);
	my $msg = pack("C*", 0xD5, 0x01) . pack("v*", length($input)+length($ID)+5) . $ID . $input . chr(0);
	$self->sendToServer($msg);
	debug "Sent talk text: ".getHex($ID).", $input\n", "sendPacket", 2;
}

# 0x011b,20,useskillmap,2:4
sub sendWarpTele { # type: 26=tele, 27=warp
	my ($self, $skillID, $map) = @_;
	my $msg = pack('v2 Z16', 0x011B, $skillID, stringToBytes($map));
	$self->sendToServer($msg);
	debug "Sent ". ($skillID == 26 ? "Teleport" : "Open Warp") . "\n", "sendPacket", 2
}
=pod
sub sendTeleport {
	my $self = shift;
	my $location = shift;
	$location = substr($location, 0, 16) if (length($location) > 16);
	$location .= chr(0) x (16 - length($location));
	my $msg = pack("C*", 0x1B, 0x01, 0x1A, 0x00) . $location;
	$self->sendToServer($msg);
	debug "Sent Teleport: $location\n", "sendPacket", 2;
}

sub sendOpenWarp {
	my ($self, $map) = @_;
	my $msg = pack("C*", 0x1b, 0x01, 0x1b, 0x00) . $map .
		chr(0) x (16 - length($map));
	$self->sendToServer($msg);
}
=cut

sub sendTop10Alchemist {
	my $self = shift;
	my $msg = pack("v", 0x0218);
	$self->sendToServer($msg);
	debug "Sent Top 10 Alchemist request\n", "sendPacket", 2;
}

sub sendTop10Blacksmith {
	my $self = shift;
	my $msg = pack("v", 0x0217);
	$self->sendToServer($msg);
	debug "Sent Top 10 Blacksmith request\n", "sendPacket", 2;
}	

sub sendTop10PK {
	my $self = shift;
	my $msg = pack("v", 0x0237);
	$self->sendToServer($msg);
	debug "Sent Top 10 PK request\n", "sendPacket", 2;	
}

sub sendTop10Taekwon {
	my $self = shift;
	my $msg = pack("v", 0x0225);
	$self->sendToServer($msg);
	debug "Sent Top 10 Taekwon request\n", "sendPacket", 2;
}

sub sendUnequip {
	my $self = shift;
	my $index = shift;
	my $msg = pack("v", 0x00AB) . pack("v*", $index);
	$self->sendToServer($msg);
	debug "Sent Unequip: $index\n", "sendPacket", 2;
}

sub sendWho {
	my $self = shift;
	my $msg = pack("v", 0x00C1);
	$self->sendToServer($msg);
	debug "Sent Who\n", "sendPacket", 2;
}

sub SendAdoptReply {
	my ($self, $parentID1, $parentID2, $result) = @_;
	my $msg = pack("v V3", 0x01F7, $parentID1, $parentID2, $result);
	$self->sendToServer($msg);
	debug "Sent Adoption Reply.\n", "sendPacket", 2;
}

sub SendAdoptRequest {
	my ($self, $ID) = @_;
	my $msg = pack("v V", 0x01F9, $ID);
	$self->sendToServer($msg);
	debug "Sent Adoption Request.\n", "sendPacket", 2;
}

# 0x0213 has no info on eA

sub sendMailboxOpen {
	my $self = $_[0];
	my $msg = pack("v", 0x023F);
	$self->sendToServer($msg);
	debug "Sent mailbox open.\n", "sendPacket", 2;
}

sub sendMailRead {
	my ($self, $mailID) = @_;
	my $msg = pack("v V", 0x0241, $mailID);
	$self->sendToServer($msg);
	debug "Sent read mail.\n", "sendPacket", 2;
}

sub sendMailDelete {
	my ($self, $mailID) = @_;
	my $msg = pack("v V", 0x0243, $mailID);
	$self->sendToServer($msg);
	debug "Sent delete mail.\n", "sendPacket", 2;
}

sub sendMailGetAttach {
	my ($self, $mailID) = @_;
	my $msg = pack("v V", 0x0244, $mailID);
	$self->sendToServer($msg);
	debug "Sent mail get attachment.\n", "sendPacket", 2;
}

sub sendMailOperateWindow {
	my ($self, $window) = @_;
	my $msg = pack("v C x", 0x0246, $window);
	$self->sendToServer($msg);
	debug "Sent mail window.\n", "sendPacket", 2;
}

sub sendMailSetAttach {
	my $self = $_[0];
	my $amount = $_[1];
	my $index = (defined $_[2]) ? $_[2] : 0;	# 0 for zeny
	my $msg = pack("v2 V", 0x0247, $index, $amount);
	$self->sendToServer($msg);
	debug "Sent mail set attachment.\n", "sendPacket", 2;
}

sub sendMailSend {
	my ($self, $receiver, $title, $message) = @_;
	my $msg = pack("v2 Z24 a40 C Z*", 0x0248, length($message)+70 , stringToBytes($receiver), stringToBytes($title), length($message), stringToBytes($message));
	$self->sendToServer($msg);
	debug "Sent mail send.\n", "sendPacket", 2;
}

sub sendAuctionAddItemCancel {
	my ($self) = @_;
	my $msg = pack("v2", 0x024B, 1);
	$self->sendToServer($msg);
	debug "Sent Auction Add Item Cancel.\n", "sendPacket", 2;
}

sub sendAuctionAddItem {
	my ($self, $index, $amount) = @_;
	my $msg = pack("v2 V", 0x024C, $index, $amount);
	$self->sendToServer($msg);
	debug "Sent Auction Add Item.\n", "sendPacket", 2;
}

sub sendAuctionCreate {
	my ($self, $price, $buynow, $hours) = @_;
	my $msg = pack("v V2 v", 0x024D, $price, $buynow, $hours);
	$self->sendToServer($msg);
	debug "Sent Auction Create.\n", "sendPacket", 2;
}

sub sendAuctionCancel {
	my ($self, $id) = @_;
	my $msg = pack("v V", 0x024E, $id);
	$self->sendToServer($msg);
	debug "Sent Auction Cancel.\n", "sendPacket", 2;
}

sub sendAuctionBuy {
	my ($self, $id, $bid) = @_;
	my $msg = pack("v V2", 0x024F, $id, $bid);
	$self->sendToServer($msg);
	debug "Sent Auction Buy.\n", "sendPacket", 2;
}

sub sendAuctionItemSearch {
	my ($self, $type, $price, $text, $page) = @_;
	$page = (defined $page) ? $page : 1;
	my $msg = pack("v2 V Z24 v", 0x0251, $type, $price, stringToBytes($text), $page);
	$self->sendToServer($msg);
	debug "Sent Auction Item Search.\n", "sendPacket", 2;
}

sub sendAuctionReqMyInfo {
	my ($self, $type) = @_;
	my $msg = pack("v2", 0x025C, $type);
	$self->sendToServer($msg);
	debug "Sent Auction Request My Info.\n", "sendPacket", 2;
}

sub sendAuctionMySellStop {
	my ($self, $id) = @_;
	my $msg = pack("v V", 0x025D, $id);
	$self->sendToServer($msg);
	debug "Sent My Sell Stop.\n", "sendPacket", 2;
}

sub sendMailReturn {
	my ($self, $mailID, $sender) = @_;
	my $msg = pack("v V Z24", 0x0273, $mailID, stringToBytes($sender));
	$self->sendToServer($msg);
	debug "Sent return mail.\n", "sendPacket", 2;
}

sub sendCashShopBuy {
	my ($self, $ID, $amount, $points) = @_;
	my $msg = pack("v v2 V", 0x0288, $ID, $amount, $points);
	$self->sendToServer($msg);
	debug "Sent My Sell Stop.\n", "sendPacket", 2;
}

sub sendAutoRevive {
	my ($self, $ID, $amount, $points) = @_;
	my $msg = pack("v", 0x0292);
	$self->sendToServer($msg);
	debug "Sent Auto Revive.\n", "sendPacket", 2;
}

sub sendMercenaryCommand {
	my ($self, $command) = @_;
	
	# 0x0 => COMMAND_REQ_NONE
	# 0x1 => COMMAND_REQ_PROPERTY
	# 0x2 => COMMAND_REQ_DELETE
	
	my $msg = pack ('v C', 0x029F, $command);
	$self->sendToServer($msg);
	debug "Sent Mercenary Command $command", "sendPacket", 2;
}

sub sendMessageIDEncryptionInitialized {
	my $self = shift;
	my $msg = pack("v", 0x02AF);
	$self->sendToServer($msg);
	debug "Sent Message ID Encryption Initialized\n", "sendPacket", 2;
}

# has the same effects as rightclicking in quest window
sub sendQuestState {
	my ($self, $questID, $state) = @_;
	my $msg = pack("v V C", 0x02B6, $questID, $state);
	$self->sendToServer($msg);
	debug "Sent Quest State.\n", "sendPacket", 2;
}

sub sendShowEquipPlayer {
	my ($self, $ID) = @_;
	my $msg = pack("v a4", 0x02D6, $ID);
	$self->sendToServer($msg);
	debug "Sent Show Equip Player.\n", "sendPacket", 2;
}

sub sendShowEquipTickbox {
	my ($self, $flag) = @_;
	my $msg = pack("v V2", 0x02D8, 0, $flag);
	$self->sendToServer($msg);
	debug "Sent Show Equip Tickbox: flag.\n", "sendPacket", 2;
}

sub sendBattlegroundChat {
	my ($self, $message) = @_;
	$message = "|00$message" if ($config{chatLangCode} && $config{chatLangCode} ne "none");
	my $msg = pack("v2 Z*", 0x02DB, length($message)+4, stringToBytes($message));
	$self->sendToServer($msg);
	debug "Sent Battleground chat.\n", "sendPacket", 2;
}

sub sendCooking {
	my ($self, $type, $nameID) = @_;
	my $msg = pack("v3", 0x025B, $type, $nameID);
	$self->sendToServer($msg);
	debug "Sent Cooking.\n", "sendPacket", 2;
}

sub sendWeaponRefine {
	my ($self, $index) = @_;
	my $msg = pack("v V", 0x0222, $index);
	$self->sendToServer($msg);
	debug "Sent Weapon Refine.\n", "sendPacket", 2;
}

# this is different from kRO
sub sendCaptchaInitiate {
	my ($self) = @_;
	my $msg = pack('v2', 0x07E5, 0x0);
	$self->sendToServer($msg);
	debug "Sending Captcha Initiate\n";
}

# captcha packet from kRO::RagexeRE_2009_09_22a
#0x07e7,32
# TODO: what is 0x20?
sub sendCaptchaAnswer {
	my ($self, $answer) = @_;
	my $msg = pack('v2 a4 a24', 0x07E7, 0x20, $accountID, $answer);
	$self->sendToServer($msg);
}

sub sendEnteringBuyVender {
	my ($self, $ID) = @_;
	my $msg = pack("C*", 0x17, 0x08) . $ID;
	$self->sendToServer($msg);
	debug "Sent Entering Buy Vender: ".getHex($ID)."\n", "sendPacket", 2;
}

sub sendProgress {
	my ($self) = @_;
	my $msg = pack("C*", 0xf1, 0x02);
	$self->sendToServer($msg);
	debug "Sent Progress Bar Finish\n", "sendPacket", 2;
}

# 0x0204,18

1;