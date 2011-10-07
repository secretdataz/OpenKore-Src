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

package Network::Receive::kRO::Sakexe_2009_02_18a;

use strict;
use base qw(Network::Receive::kRO::Sakexe_2009_01_14a);
use Log qw(debug);
use Translation qw(TF);

sub new {
	my ($class) = @_;
	my $self = $class->SUPER::new(@_);
	my %packets = (
		'0446' => ['actor_quest_effect', 'a4 v4', [qw(ID x y effect type)]], # 14
	);
	
	foreach my $switch (keys %packets) {
		$self->{packet_list}{$switch} = $packets{$switch};
	}

	return $self;
}
sub actor_quest_effect {
	my ($self, $args) = @_;
	my $actor = Actor::get($args->{ID});
	debug TF("npc: %s (%d, %d) effect: %d (type: %d)\n", $actor, $args->{x}, $args->{y}, $args->{effect}, $args->{type});
}
=pod
//2009-02-18aSakexe
0x0446,14
=cut

1;