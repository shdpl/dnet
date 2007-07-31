/*

Copyright (c) 2007 Dmitry Shalkhakov <dmitry dot shalkhakov at gmail dot com>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

module dnet.internal.protocol;

private import dnet.buffer;
private import dnet.socket;
private import dnet.fifo;

public const {
	size_t	PACKET_SIZE			= 1400;		/// Max. size of a single packet, in bytes
	size_t	MESSAGE_SIZE		= 16384;	/// Max. size of a message, in bytes
}

private const {
	int FRAGMENT_SIZE			= PACKET_SIZE - 100;
	int FRAGMENT_BIT			= 1 << 31;
	int PACKET_HEADER_SIZE		= 4;
}

private alias ubyte[PACKET_SIZE]	PacketBuf;
private alias ubyte[MESSAGE_SIZE]	MsgBuf;

/**
	Fragments messages into packets that get sent over the wire
	and assembled back on the remote side.
*/
struct Protocol {

	// simulation variables
	int		simLoss;				// simulated packet loss, in percent
	int		simLatency;				// simulated packet latency, in ms
	int		simJitter;				// simulated network jitter, in ms

	int		dropCount;				// the number of packets dropped
									// between current and previous

	// sequence numbers
	int		incomingSequence;
	int		outgoingSequence;

	// incoming fragment buffer
	int		incomingFragmentSequence;
	int		incomingFragmentLength;
	MsgBuf	incomingFragmentBuffer;

	// outgoing fragment buffer
	bool	outgoingFragments;
	int		outgoingFragmentOffset;
	int		outgoingFragmentLength;
	MsgBuf	outgoingFragmentBuffer;

	/**
		Clears internal state.
	*/
	void clear() {
		dropCount = 0;

		incomingSequence = 0;
		outgoingSequence = 1;

		incomingFragmentSequence	= 0;
		incomingFragmentLength		= 0;
		incomingFragmentBuffer[]	= 0;

		outgoingFragments			= false;
		outgoingFragmentOffset		= 0;
		outgoingFragmentLength		= 0;
		outgoingFragmentBuffer[]	= 0;
	}

	/**
		Sends a message.
	*/
	void dispatch( ubyte[] data, DnetSocket socket, DnetAddress to ) {
		if ( outgoingFragments ) {
			throw new Exception( "Protocol.transmit: unsent outgoing fragments" );
		}

		// fragment large messages
		if ( data.length >= FRAGMENT_SIZE ) {
			outgoingFragments = true;
			outgoingFragmentOffset = 0;
			outgoingFragmentLength = data.length;
			outgoingFragmentBuffer[0..data.length] = data[];

			// only send the first fragment now
			dispatchNextFragment( socket, to );
			return;
		}

		//
		// write the packet header
		//

		PacketBuf	packetBuffer = void;
		auto		packet = DnetBuffer( packetBuffer );

		// write the sequence
		packet.putInt( outgoingSequence );

		// write the packet data
		packet.putData( data );

		// increment outgoing sequence
		outgoingSequence++;

		// send the packet
		socket.sendTo( packet.getBuffer(), to );
	}

	/**
		Sends next fragment.
	*/
	void dispatchNextFragment( DnetSocket socket, DnetAddress to ) {
		int			fragmentLength;

		if ( !outgoingFragments ) {
			throw new Exception( "Protocol.transmitNextFragment: no unsent fragments" );
		}

		if ( outgoingFragmentOffset + FRAGMENT_SIZE > outgoingFragmentLength ) {
			fragmentLength = outgoingFragmentLength - outgoingFragmentOffset;
		}
		else {
			fragmentLength = FRAGMENT_SIZE;
		}

		PacketBuf	packetBuffer = void;
		auto		packet = DnetBuffer( packetBuffer );

		// write the packet header
		packet.putInt( outgoingSequence | FRAGMENT_BIT );

		// write the fragment offset and length
		packet.putUshort( outgoingFragmentOffset );
		packet.putUshort( fragmentLength );

		// write the packet data
		packet.putData( outgoingFragmentBuffer[outgoingFragmentOffset..outgoingFragmentOffset + fragmentLength] );

		outgoingFragmentOffset += fragmentLength;

		// This exit condition is a little tricky, because a packet that is exactly
		// the fragment size still needs to send a second packet of zero length so
		// that the other side can tell there aren't more to follow
		if ( outgoingFragmentOffset == outgoingFragmentLength && fragmentLength != FRAGMENT_SIZE ) {
			outgoingFragments = false;

			outgoingSequence++;
		}

		// send the packet
		socket.sendTo( packet.getBuffer, to );
	}

	/**
		Decides whether a packet is correctly sequenced and therefore should be
		processed.
		msg is the message.
		Returns: true if the message should be processed,
		false if it should be discarded.
	*/
	bool process( ref DnetBuffer msg ) {
		bool		fragmented;
		ushort		fragmentOffset, fragmentLength;

		// read the sequence number
		int sequence = msg.readInt();

		// check for fragmented message
		if ( sequence & FRAGMENT_BIT ) {
			sequence &= ~FRAGMENT_BIT;
			fragmented = true;
		}

		// read the fragment offset and size if a fragmented message
		if ( fragmented ) {
			fragmentOffset = msg.readUshort();
			fragmentLength = msg.readUshort();
		}

		// discard out-of-order and duplicated packets
		if ( sequence <= incomingSequence ) {
			return false;
		}

		dropCount = sequence - ( incomingSequence + 1 );

		// assemble fragments
		if ( fragmented ) {
			// make sure we add the fragments in correct order
			if ( incomingFragmentSequence != sequence ) {
				incomingFragmentSequence = sequence;
				incomingFragmentLength = 0;
			}

			// if we missed a fragment, dump it
			if ( incomingFragmentLength != fragmentOffset ) {
				return false;
			}

			// copy the fragment to the fragment buffer
			if ( incomingFragmentLength + fragmentLength > incomingFragmentBuffer.sizeof || msg.bytesRead + fragmentLength > msg.length || ( fragmentLength < 0 || fragmentLength > FRAGMENT_SIZE ) ) {
				return false;
			}

			msg.readData( incomingFragmentBuffer[incomingFragmentLength..fragmentLength] );

			incomingFragmentLength += fragmentLength;

			// if this wasn't the last fragment, don't process anything
			if ( fragmentLength == FRAGMENT_SIZE ) {
				return false;
			}

			// copy the full message
			msg.clear();

			msg.putInt( sequence );
			msg.putData( incomingFragmentBuffer[0..incomingFragmentLength] );

			// set the read state
			msg.beginReading( PACKET_HEADER_SIZE );
		}

		incomingSequence = sequence;

		return true;	// should be processed
	}

	/**
		Returns true if there are unsent fragments of the previous message.
	*/
	bool hasUnsentFragments() {
		return outgoingFragments;
	}

	/**
		Returns outgoing sequence number.
	*/
	int sequence() {
		return outgoingSequence;
	}
}
