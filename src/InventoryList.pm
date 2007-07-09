#########################################################################
#  OpenKore - Inventory list
#
#  Copyright (c) 2007 OpenKore Development Team
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#########################################################################
##
# MODULE DESCRIPTION: Inventory model
#
# <b>Derived from: @CLASS(ObjectList)</b>
#
# The InventoryList class models a character's inventory or a Kapra storage.
#
# <h3>Differences compared to ObjectList</h3>
# All items in ActorList are of the same class, and are all a
# subclass of @CLASS(Actor::Item).
package InventoryList;

use strict;
use Carp::Assert;
use Utils::ObjectList;
use base qw(ObjectList);

### CATEGORY: Class InventoryList

##
# InventoryList InventoryList->new()
# Ensures:  $self->size() == 0
#
# Creates a new InventoryList object.
sub new {
	my ($class) = @_;
	my $self = $class->SUPER::new();

	# Hash<String, Actor::Item> nameIndex
	# Maps an item name to an Actor::Item object. Used
	# for fast lookups of items based on names.
	#
	# Invariant:
	#     defined(nameIndex)
	#     scalar(keys nameIndex) == size()
	#     for all values $v in nameIndex:
	#         find($v) != -1
	$self->{nameIndex} = {};

	return $self;
}

##
# int $InventoryList->add(Actor::Item item)
# Requires:
#     defined($item)
#     defined($item->{name})
#     $self->find($item) == -1
# Ensures: $item->{invIndex} == result
#
# Adds an item to this InventoryList. $item->{invIndex} will automatically be set
# index in which that item is stored in this list.
#
# This method overloads $Object->add(), and has a stronger precondition.
# See the documentation for that method for more information about this
# method.
sub add {
	my ($self, $item) = @_;
	assert(defined $item) if DEBUG;
	assert($item->isa('Actor::Item')) if DEBUG;
	assert(defined $item->{name}) if DEBUG;
	assert(!exists $self->{nameIndex}{$item->{name}}) if DEBUG;

	$self->{nameIndex}{$item->{name}} = $item;
	my $invIndex = $self->SUPER::add($item);
	$item->{invIndex} = $invIndex;
	return $invIndex;
}

##
# Actor::Item $InventoryList->getByName(String name)
# Returns: An Actor::Item, or undef if there is no item with that name in this list.
# Requires: defined($name)
# Ensures: if defined(result): result->{ID} eq $ID
#
# Looks up an Actor::Item object based on the item name.
#
# See also: $Actor->{ID}
sub getByName {
	my ($self, $name) = @_;
	assert(defined $name) if DEBUG;
	return $self->{nameIndex}{$name};
}

##
# Actor::Item $InventoryList->getByServerIndex(int serverIndex)
#
# Return the first Actor::Item object, whose 'index' field is equal to $serverIndex.
# If nothing is found, undef is returned.
sub getByServerIndex {
	my ($self, $serverIndex) = @_;
	foreach my $item (@{$self->getItems()}) {
		if ($item->{index} == $serverIndex) {
			return $item;
		}
	}
	return undef;
}

##
# boolean $InventoryList->remove(Actor::Item item)
# Requires: defined($item) && defined($item->{name})
#
# Removes an item from this InventoryList.
#
# This method overloads $ObjectList->remove(), and has a stronger precondition.
# See the documentation for that method for more information about this
# method.
sub remove {
	my ($self, $item) = @_;
	assert(defined $item) if DEBUG;
	assert(UNIVERSAL::isa($item, 'Actor::Item')) if DEBUG;
	assert(defined $item->{name}) if DEBUG;

	my $result = $self->SUPER::remove($item);
	if ($result) {
		delete $self->{nameIndex}{$item->{name}};
	}
	return $result;
}

##
# boolean $InventoryList->removeByName(String name)
# name: The name of the item to remove.
# Returns: Whether the item with the specified name was in the list.
# Requires: defined($name)
#
# Removes an item based on the item name. This will trigger an onRemove event
# before the item is removed.
sub removeByName {
	my ($self, $name) = @_;
	my $item = $self->getByName($name);
	if (defined $item) {
		return $self->remove($item);
	} else {
		return 0;
	}
}

# overloaded
sub doClear {
	my ($self) = @_;
	$self->SUPER::doClear();
	$self->{nameIndex} = {};
}

# overloaded
sub checkValidity {
	my ($self) = @_;
	$self->SUPER::checkValidity();

	assert(defined $self->{nameIndex});
	should(scalar(keys %{$self->{nameIndex}}), $self->size());
	foreach my $v (values %{$self->{nameIndex}}) {
		assert($self->find($v) != -1);
	}
}

1;
