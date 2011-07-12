#########################################################################
#  OpenKore - Packet sending
#  This module contains functions for sending packets to the server.
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#
#  $Revision: 6687 $
#  $Id: kRO.pm 6687 2009-04-19 19:04:25Z technologyguild $
########################################################################
# Korea (kRO)
# The majority of private servers use eAthena, this is a clone of kRO

package Network::Send::kRO::Sakexe_2005_06_28a;

use strict;
use base qw(Network::Send::kRO::Sakexe_2005_06_22a);

use Log qw(message warning error debug);
use Utils qw(getTickCount getHex getCoordString);

# TODO: maybe we should try to not use globals in here at all but instead pass them on?
use Globals qw($char);

sub version {
	return 17;
}

sub new {
	my ($class) = @_;
	my $self = $class->SUPER::new(@_);
	
	my %packets = (
		'0085' => ['actor_look_at', 'x6 C x9 C', [qw(head body)]],
		'0089' => ['sync'], # TODO
		'009B' => ['map_login', 'x7 a4 x4 a4 x4 a4 V C', [qw(accountID charID sessionID tick sex)]],
		'00F5' => ['item_take', 'x7 a4', [qw(ID)]],
		'0190' => ['actor_action', 'x9 a4 x8 C', [qw(targetID type)]],
	);
	$self->{packet_list}{$_} = $packets{$_} for keys %packets;
	
	$self;
}

# 0x0072,34,useskilltoid,6:17:30
sub sendSkillUse {
	my ($self, $ID, $lv, $targetID) = @_;
	my $msg;

	my %args;
	$args{ID} = $ID;
	$args{lv} = $lv;
	$args{targetID} = $targetID;
	Plugins::callHook('packet_pre/sendSkillUse', \%args);
	if ($args{return}) {
		$self->sendToServer($args{msg});
		return;
	}

	$msg = pack('v x4 V x7 v x11 a4', 0x0072, $lv, $ID, $targetID);
	$self->sendToServer($msg);
	debug "Skill Use: $ID\n", "sendPacket", 2;
}

# 0x007e,113,useskilltoposinfo,12:15:18:31:33
sub sendSkillUseLocInfo {
	my ($self, $ID, $lv, $x, $y, $moreinfo) = @_;

	my $msg = pack('v x10 v x v x v x11 v Z80', 0x007E, $lv, $ID, $x, $y, $moreinfo);

	$self->sendToServer($msg);
	debug "Skill Use on Location: $ID, ($x, $y)\n", "sendPacket", 2;
}

# 0x0085,17,changedir,8:16

# 0x0089,13,ticksend,9
sub sendSync {
	my ($self, $initialSync) = @_;
	my $msg;
	# XKore mode 1 lets the client take care of syncing.
	return if ($self->{net}->version == 1);

	$msg = pack('v x7 V', 0x0089, getTickCount());
	$self->sendToServer($msg);
	debug "Sent Sync\n", "sendPacket", 2;
}

# 0x008c,8,getcharnamerequest,4
sub sendGetPlayerInfo {
	my ($self, $ID) = @_;
	my $msg = pack('v x2 a4', 0x008C, $ID);
	$self->sendToServer($msg);
	debug "Sent get player info: ID - ".getHex($ID)."\n", "sendPacket", 2;
}

# 0x0094,31,movetokafra,16:27
sub sendStorageAdd {
	my ($self, $index, $amount) = @_;
	my $msg = pack('v x14 v x9 V', 0x0094, $index, $amount);
	$self->sendToServer($msg);
	debug "Sent Storage Add: $index x $amount\n", "sendPacket", 2;
}

# 0x009b,32,wanttoconnection,9:15:23:27:31

# 0x009f,19,useitem,9:15
sub sendItemUse {
	my ($self, $ID, $targetID) = @_;
	my $msg = pack('v x7 v x4 a4', 0x009F, $ID, $targetID);
	$self->sendToServer($msg);
	debug "Item Use: $ID\n", "sendPacket", 2;
}

# 0x00a2,9,solvecharname,5
sub sendGetCharacterName {
	my ($self, $ID) = @_;
	my $msg = pack('v x3 a4', 0x00A2, $ID);
	$self->sendToServer($msg);
	debug "Sent get character name: ID - ".getHex($ID)."\n", "sendPacket", 2;
}

# 0x00a7,11,walktoxy,8
sub sendMove {
	my ($self, $x, $y) = @_;
	my $msg = pack('v x6 a3', 0x00A7, getCoordString($x = int $x, $y = int $y, 1));
	$self->sendToServer($msg);
	debug "Sent move to: $x, $y\n", "sendPacket", 2;
}

# 0x00f5,13,takeitem,9

# 0x00f7,18,movefromkafra,11:14
sub sendStorageGet {
	my ($self, $index, $amount) = @_;
	my $msg = pack('v x9 v x3 V', 0x00F7, $index, $amount);
	$self->sendToServer($msg);
	debug "Sent Storage Get: $index x $amount\n", "sendPacket", 2;
}

# 0x0113,33,useskilltopos,12:15:18:31
sub sendSkillUseLoc {
	my ($self, $ID, $lv, $x, $y) = @_;
	my $msg = pack('v x10 v x v x v x11 v', 0x0113, $lv, $ID, $x, $y);
	$self->sendToServer($msg);
	debug "Skill Use on Location: $ID, ($x, $y)\n", "sendPacket", 2;
}

# 0x0116,12,dropitem,3:10
sub sendDrop {
	my ($self, $index, $amount) = @_;
	my $msg = pack('v x v x5 v', 0x0113, $index, $amount);
	$self->sendToServer($msg);
	debug "Sent drop: $index x $amount\n", "sendPacket", 2;
}

# 0x0190,24,actionrequest,11:23

=pod
//2005-06-28aSakexe
packet_ver: 17
0x0072,34,useskilltoid,6:17:30
0x007e,113,useskilltoposinfo,12:15:18:31:33
0x0085,17,changedir,8:16
0x0089,13,ticksend,9
0x008c,8,getcharnamerequest,4
0x0094,31,movetokafra,16:27
0x009b,32,wanttoconnection,9:15:23:27:31
0x009f,19,useitem,9:15
0x00a2,9,solvecharname,5
0x00a7,11,walktoxy,8
0x00f5,13,takeitem,9
0x00f7,18,movefromkafra,11:14
0x0113,33,useskilltopos,12:15:18:31
0x0116,12,dropitem,3:10
0x0190,24,actionrequest,11:23
0x0216,0
0x023d,-1
0x023e,4
=cut

1;