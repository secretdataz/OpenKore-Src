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
# tRO (Thai) for 2008-09-16Ragexe12_Th
# Servertype overview: http://www.openkore.com/wiki/index.php/ServerType
package Network::Send::twRO;

use strict;
use Globals;
use Network::Send::ServerType0;
use base qw(Network::Send::ServerType0);
use Log qw(error debug);
use I18N qw(stringToBytes);
use Utils qw(getTickCount getHex getCoordString);

sub new {
   my ($class) = @_;
   return $class->SUPER::new(@_);
}

sub sendMove {
   my $self = shift;
   my $x = int scalar shift;
   my $y = int scalar shift;
   my $msg;

   $msg = pack("C*", 0x85, 0x00) . getCoordString($x, $y, 1);

   $self->sendToServer($msg);
   debug "Sent move to: $x, $y\n", "sendPacket", 2;
}

sub sendHomunculusMove {
	my $self = shift;
	my $homunID = shift;
	my $x = int scalar shift;
	my $y = int scalar shift;
	my $msg = pack("C*", 0x32, 0x02) . $homunID . getCoordString($x, $y, 1);
	$self->sendToServer($msg);
	debug "Sent Homunculus move to: $x, $y\n", "sendPacket", 2;
}

sub sendBuyBulkVender {
	my ($self, $venderID, $r_array, $venderCID) = @_;
	my $msg = pack('v2 a4 a4', 0x0801, 12+4*@{$r_array}, $venderID, $venderCID);
	for (my $i = 0; $i < @{$r_array}; $i++) {
		$msg .= pack('v2', $r_array->[$i]{amount}, $r_array->[$i]{itemIndex});
		debug "Sent bulk buy vender: $r_array->[$i]{itemIndex} x $r_array->[$i]{amount}\n", "d_sendPacket", 2;
	}
	$self->sendToServer($msg);
}
1;