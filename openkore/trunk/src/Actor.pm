#########################################################################
#  OpenKore - Base class for all actor objects
#  Copyright (c) 2005 OpenKore Team
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
# MODULE DESCRIPTION: Base class for all actor objects
#
# The Actor class is a base class for all actor objects.
# An actor object is a monster or player (all members of %monsters and
# %players). Do not create an object of this class; use one of the
# subclasses instead.
#
# An actor object is also a hash.
#
# Child classes: @MODULE(Actor::Monster), @MODULE(Actor::Player) and @MODULE(Actor::You)

package Actor;

use strict;
use Carp::Assert;
use Scalar::Util;
use Globals;
use Utils;
use Log qw(message error debug);
use Misc;

# Make it so that
#     print $actor;
# acts the same as
#     print $actor->nameString;
use overload '""' => \&_nameString;
# The eq operator checks whether two variables refer to compatible objects.
use overload 'eq' => \&_eq;
use overload 'ne' => \&_ne;
# The == operator is to check whether two variables refer to the
# exact same object.
use overload '==' => \&_isis;
use overload '!=' => \&_not_is;

sub _eq {
	return UNIVERSAL::isa($_[0], "Actor")
		&& UNIVERSAL::isa($_[1], "Actor")
		&& $_[0]->{ID} eq $_[1]->{ID};
}

sub _ne {
	return !&_eq;
}

# This function is needed to make the operator overload respect inheritance.
sub _nameString {
	my $self = shift;
	return $self->nameString(@_);
}

sub _isis {
	return Scalar::Util::refaddr($_[0]) == Scalar::Util::refaddr($_[1]);
}

sub _not_is {
	return !&_isis;
}

### CATEGORY: Class methods

##
# Actor Actor::get(Bytes ID)
# ID: an actor ID.
# Returns: the associated Actor object, or a new Actor::Unknown object if not found.
# Requires: defined($ID)
# Ensures:  defined(result)
#
# Returns the Actor object for $ID.
sub get {
	my ($ID) = @_;
	assert(defined $ID) if DEBUG;

	if ($ID eq $accountID) {
		return $char;
	} elsif ($playersList->getByID($ID)) {
		return $playersList->getByID($ID);
	} elsif ($monstersList->getByID($ID)) {
		return $monstersList->getByID($ID);
	} elsif ($npcsList->getByID($ID)) {
		return $npcsList->getByID($ID);
	} elsif ($petsList->getByID($ID)) {
		return $petsList->getByID($ID);
	} elsif ($portalsList->getByID($ID)) {
		return $portalsList->getByID($ID);
	} elsif (exists $items{$ID}) {
		return $items{$ID};
	} else {
		return new Actor::Unknown($ID);
	}
}

### CATEGORY: Hash members

##
# String $Actor->{type}
# Invariant: defined(value)
#
# An identifier for this actor's type. The meaning for this field
# depends on the actor's class. For example, for Player actors,
# this is the job ID (though you should use $ActorPlayer->{jobID} instead).

##
# int $Actor->{binID}
# Invariant: value >= 0
#
# The index of this actor inside its associated actor list.

##
# Bytes $Actor->{ID}
# Invariant: length(value) == 4
#
# The server's internal unique ID for this actor (the actor's account ID).

##
# int $Actor->{nameID}
# Invariant: value >= 0
#
# $Actor->{ID} decoded into an 32-bit little endian integer.

##
# int $Actor->{appear_time}
# Invariant: value >= 0
#
# The time when this actor first appeared on screen.

##
# String $Actor->{actorType}
# Invariant: defined(value)
#
# A human-friendly name which describes this actor type.
# For instance, "Player", "Monster", "NPC", "You", etc.
# Do not confuse this with $Actor->{type}


### CATEGORY: Methods

##
# String $Actor->nameString([Actor otherActor])
#
# Returns the name string of an actor, e.g. "Player pmak (3)",
# "Monster Poring (0)" or "You".
#
# If $otherActor is specified and is equal to $actor, then it will
# return 'self' or 'yourself' instead.
sub nameString {
	my ($self, $otherActor) = @_;

	return $self->selfString if $self->{ID} eq $otherActor->{ID};

	my $nameString = "$self->{actorType} " . $self->name;
	$nameString .= " ($self->{binID})" if defined $self->{binID};
	return $nameString;
}

##
# String $Actor->selfString()
#
# Returns 'itself' for monsters, or 'himself/herself' for players.
# ('yourself' is handled by Actor::You.nameString.)
sub selfString {
	return 'itself';
}

##
# String $Actor->name()
#
# Returns the name of an actor, e.g. "pmak" or "Unknown #300001".
sub name {
	my ($self) = @_;

	return $self->{name} || "Unknown #".unpack("V1", $self->{ID});
}

##
# String $Actor->nameIdx()
#
# Returns the name and index of an actor, e.g. "pmak (0)" or "Unknown #300001 (1)".
sub nameIdx {
	my ($self) = @_;

	my $nameIdx = $self->name;
	$nameIdx .= " ($self->{binID})" if defined $self->{binID};
	return $nameIdx;

#	return $self->{name} || "Unknown #".unpack("V1", $self->{ID});
}

##
# String $Actor->verb(Actor you, Actor other)
#
# Returns $you if $actor is you; $other otherwise.
sub verb {
	my ($self, $you, $other) = @_;

	return $you if $self->isa('Actor::You');
	return $other;
}

##
# Hash $Actor->position()
#
# Returns the position of the actor.
sub position {
	my ($self) = @_;

	return calcPosition($self);
}

##
# float $Actor->distance([Actor otherActor])
#
# Returns the distance to another actor (defaults to yourself).
sub distance {
	my ($self, $otherActor) = @_;

	$otherActor ||= $char;
	return Utils::distance($self->position, $otherActor->position);
}

##
# float $Actor->blockDistance([Actor otherActor])
#
# Returns the block distance to another actor (defaults to yourself).
sub blockDistance {
	my ($self, $otherActor) = @_;

	$otherActor ||= $char;
	return Utils::blockDistance($self->position, $otherActor->position);
}

##
# boolean $Actor->snipable()
#
# Returns whether or not you have snipable LOS to the actor.
sub snipable {
	my ($self) = @_;

	return checkLineSnipable($char->position, $self->position);
}

1;
