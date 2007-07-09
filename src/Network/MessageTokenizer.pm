#########################################################################
#  OpenKore - Networking subsystem
#  This module contains functions for sending packets to the server.
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#########################################################################
##
# MODULE DESCRIPTION: Conversion of byte stream to descrete messages.
#
# As explained by the <a href="http://www.openkore.com/wiki/index.php/Network_subsystem">
# network subsystem overview</a>, the Ragnarok Online protocol uses TCP, which means
# that all server messages are received as a byte stream.
# This class is specialized in extracting discrete RO server or client messages from a byte
# stream.
package Network::MessageTokenizer;

use strict;
use Carp::Assert;
use Exception::Class qw(Network::MessageTokenizer::Unknownmessage);
use Modules 'register';
use bytes;
no encoding 'utf8';

##
# Network::MessageTokenizer->new(Hash* rpackets)
# rpackets: A reference to a hash containing the packet length database.
# Required: defined($rpackets)
#
# Create a new Network::MessageTokenizer object.
sub new {
	my ($class, $rpackets) = @_;
	assert(defined $rpackets) if DEBUG;
	my %self = (
		rpackets => $rpackets,
		buffer => ''
	);
	return bless \%self, $class;
}

##
# void $Network_MessageTokenizer->add(Bytes data)
# Requires: defined($data)
#
# Add raw data to this tokenizer's buffer.
sub add {
	my ($self, $data) = @_;
	assert(defined $data) if DEBUG;
	$self->{buffer} .= $data;
}

##
# void $Network_MessageTokenizer->clear()
#
# Clear the internal buffer.
sub clear {
	$_[0]->{buffer} = '';
}

##
# String Network::MessageTokenizer::getMessageID(Bytes message)
# Requires: length($message) >= 2
#
# Extract the message ID (also known as the "packet switch") from the given message.
sub getMessageID {
	return uc(unpack("H2", substr($_[0], 1, 1))) . uc(unpack("H2", substr($_[0], 0, 1)));
}

##
# Bytes $Network->MessageTokenizer->getBuffer()
# Ensures: defined(result)
#
# Get the internal buffer.
sub getBuffer {
	return $_[0]->{buffer};
}

##
# Bytes $Network_MessageTokenizer->readNext()
#
# Read the next full message from the buffer, if there is one.
# If not, undef will be returned.
sub readNext {
	my ($self) = @_;

	return undef if (length($self->{buffer}) < 2);

	my $switch = getMessageID($self->{buffer});
	my $rpackets = $self->{rpackets};
	my $size;

	if ($rpackets->{$switch} eq '-' || $switch eq "0070") {
		# Complete message; the size of this message is equal
		# to the size of the entire TCP packet.
		$size = length($self->{buffer});

	} elsif ($rpackets->{$switch} eq '0') {
		# Variable length message.
		if (length($self->{buffer}) < 4) {
			return undef;
		}
		$size = unpack("v", substr($self->{buffer}, 2, 2));
		if (length($self->{buffer}) < $size) {
			return undef;
		}

	} elsif ($rpackets->{$switch} > 1) {
		# Static length message.
		$size = $rpackets->{$switch};
		if (length($self->{buffer}) < $size) {
			return undef;
		}

	} else {
		Network::MessageTokenizer::Unknownmessage->throw("Unknown message '$switch'.");
	}

	my $result = substr($self->{buffer}, 0, $size);
	substr($self->{buffer}, 0, $size, '');
	return $result;
}

1;
