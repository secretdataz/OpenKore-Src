package AI::Slave::Mercenary;
use Log qw/message warning error debug/;

use strict;
use base qw/AI::Slave/;
use Globals;
use Log qw/message warning error debug/;
use AI;
use Utils;
use Misc;
use Translation;

sub checkSkillOwnership { $_[1]->getOwnerType == Skill::OWNER_MERC }

1;
