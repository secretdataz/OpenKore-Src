# bRO (Brazil)
package Network::Send::bRO;
use strict;
use Globals;
use Log qw(message warning error debug);
use Utils qw(existsInList getHex getTickCount getCoordString);
use Math::BigInt;
use base 'Network::Send::ServerType0';
use I18N qw(stringToBytes);

sub new {
	my ($class) = @_;
	my $self = $class->SUPER::new(@_);

	my %packets = (
		'0108' => ['party_chat', 'x2 Z*', [qw(message)]],
		'096A' => ['actor_info_request', 'a4', [qw(ID)]],
		'0437' => ['character_move','a3', [qw(coords)]],
		'012E' => ['shop_close'],
		'09CB' => ['private_message', 'x2 Z24 Z*', [qw(privMsgUser privMsg)]],
		'07E4' => ['item_take', 'a4', [qw(ID)]],
		'01B2' => ['shop_open'],
		'0202' => ['actor_look_at', 'v C', [qw(head body)]],
		'008C' => ['public_chat', 'x2 Z*', [qw(message)]],
		'022D' => ['map_login', 'a4 a4 a4 V C', [qw(accountID charID sessionID tick sex)]],
		'07D7' => ['party_setting', 'V C2', [qw(exp itemPickup itemDivision)]],
		'017E' => ['guild_chat', 'x2 Z*', [qw(message)]],
		'0369' => ['actor_action', 'a4 C', [qw(targetID type)]],
		'0361' => ['homunculus_command', 'v C', [qw(commandType, commandID)]],
		'0443' => ['skill_select', 'V v', [qw(why skillID)]],
		'035F' => ['sync', 'V', [qw(time)]],
		'023B' => ['party_join_request_by_name', 'Z24', [qw(partyName)]],
		'0438' => ['skill_use_location', 'v4', [qw(lv skillID x y)]],
		'0362' => ['item_drop', 'v2', [qw(index amount)]],
		'0364' => ['storage_item_remove', 'v V', [qw(index amount)]],
		'07EC' => ['storage_item_add', 'v V', [qw(index amount)]],
	);

	$self->{packet_list}{$_} = $packets{$_} for keys %packets;

	my %handlers = qw(
		guild_chat 017E
		buy_bulk_vender 0801
		item_take 07E4
		actor_look_at 0202
		private_message 09CB
		character_move 0437
		actor_info_request 096A
		party_setting 07D7
		party_chat 0108
		shop_open 01B2
		storage_item_remove 0364
		shop_close 012E
		storage_item_add 07EC
		item_drop 0362
		sync 035F
		skill_select 0443
		homunculus_command 0361
		public_chat 008C
		party_setting 07D7
		actor_action 0369
		party_join_request_by_name 023B
		master_login 02B0
		skill_use_location 0438
		map_login 022D
	);

	$self->{packet_lut}{$_} = $handlers{$_} for keys %handlers;

	return $self;
}

# Local Servertype Globals
my $map_login = 0;
my $enc_val3 = 0;

sub encryptMessageID 
{
	my ($self, $r_message, $MID) = @_;

	# Checking In-Game State
	if ($self->{net}->getState() != Network::IN_GAME && !$map_login) { $enc_val1 = 0; $enc_val2 = 0; return; }

	# Turn Off Map Login Flag
	if ($map_login)	{ $map_login = 0; }

	# Checking if Encryption is Activated
	if ($enc_val1 != 0 && $enc_val2 != 0) 
	{
		# Saving Last Informations for Debug Log
		my $oldMID = $MID;
		my $oldKey = ($enc_val1 >> 8 >> 8) & 0x7FFF;

		# Calculating the Encryption Key
		$enc_val1 = $enc_val1->bmul($enc_val3)->badd($enc_val2) & 0xFFFFFFFF;

		# Xoring the Message ID
		$MID = ($MID ^ (($enc_val1 >> 8 >> 8) & 0x7FFF)) & 0xFFFF;
		$$r_message = pack("v", $MID) . substr($$r_message, 2);

		# Debug Log
		if ($config{debugPacket_sent} == 1) 
		{
			debug(sprintf("Encrypted MID : [%04X]->[%04X] / KEY : [0x%04X]->[0x%04X]\n", $oldMID, $MID, $oldKey, ($enc_val1 >> 8 >> 8) & 0x7FFF), "sendPacket", 0);
		}
	}
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
		$msg = pack("v v", 0x08A7, $type).$pass.pack("H*", "EC62E539BB6BBC811A60C06FACCB7EC8");
	} elsif ($type == 2) {
		$msg = pack("v v", 0x08A7, $type).pack("H*", "EC62E539BB6BBC811A60C06FACCB7EC8").$pass;
	} else {
		ArgumentException->throw("The 'type' argument has invalid value ($type).");
	}
	$self->sendToServer($msg);
}

sub sendMapLogin 
{
	my ($self, $accountID, $charID, $sessionID, $sex) = @_;
	my $msg;

	$sex = 0 if ($sex > 1 || $sex < 0); # Sex can only be 0 (female) or 1 (male)

	if ( $map_login == 0 ) { PrepareKeys(); $map_login = 1; }

	# Reconstructing Packet 
	$msg = $self->reconstruct({
		switch => 'map_login',
		accountID => $accountID,
		charID => $charID,
		sessionID => $sessionID,
		tick => getTickCount,
		sex => $sex,
	});

	$self->sendToServer($msg);
	debug "Sent sendMapLogin\n", "sendPacket", 2;
}

sub sendHomunculusCommand 
{
	my ($self, $command, $type) = @_; # $type is ignored, $command can be 0:get stats, 1:feed or 2:fire

	$self->sendToServer($self->reconstruct({
		switch => 'homunculus_command',
		commandType => $type,
		commandID => $command,
	}));

	debug "Sent Homunculus Command $command", "sendPacket", 2;
}

sub sendPartyJoinRequestByName 
{
	my ($self, $name) = @_;

	$self->sendToServer($self->reconstruct({
		switch => 'party_join_request_by_name',
		partyName => stringToBytes ($name),
	}));

	debug "Sent Request Join Party (by name): $name\n", "sendPacket", 2;
}

sub PrepareKeys()
{
	# K
	$enc_val1 = Math::BigInt->new('0x72DA72DA');
	# M
	$enc_val2 = Math::BigInt->new('0x72DA72DA');
	# A
	$enc_val3 = Math::BigInt->new('0x72DA72DA');
}

1;
