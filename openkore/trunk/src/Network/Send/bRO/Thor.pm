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
# bRO (Brazil): Thor
# Servertype overview: http://www.openkore.com/wiki/index.php/ServerType
package Network::Send::bRO::Thor;

use strict;
use Globals;
use Network::Send::bRO;
use base qw(Network::Send::bRO);
use Log qw(error debug);
use I18N qw(stringToBytes);
use Utils qw(getTickCount getHex getCoordString);

sub new {
   my ($class) = @_;
   return $class->SUPER::new(@_);
}


1;