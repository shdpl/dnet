/**
	Copyright: (c) 2007 DNet Team
	Authors: DNet Team, see AUTHORS file
	License: MIT-style, see LICENSE file
*/
module dnet.channel;

version ( Tango ) {
	import tango.text.convert.Sprint;
}
else {
	import std.format;
}

import dnet.buffer;
import dnet.socket;
import dnet.utils;
import dnet.protocol;

package const PACKET_LENGTH			= 1400;		/// Maximum length of a packet.

/**
	Network channel does message fragmenting and filtering of out-of-date and duplicate packets.
*/
package struct DnetChannel {
	private const FRAGMENT_SIZE			= PACKET_LENGTH - 100;
	private const FRAGMENT_BIT			= 1 << 31;

	/**
		Call when a connection to the remote system has been established.
	*/
	void setup( Socket socket, Address remoteAddress ) {
		clear();
		this.socket = socket;
		this.remoteAddress = remoteAddress;
	}

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
		Transmits an unsequenced packet.
	*/
	version ( Tango ) {
		static void transmitOOB( Socket sock, Address to, char[] fmt, ... ) {
			ubyte[PACKET_LENGTH]	buf;
			int						bufLen;
			char[]					s;

			// format args
			scope sprint = new Sprint!( char )( PACKET_LENGTH-4 );

			s = sprint.format( fmt, _arguments, _argptr );
			bufLen = s.length + 4;

			// write the packet
			*cast( int * )buf[0..4] = -1;
			buf[4..bufLen] = cast( ubyte[] )s[];

			// dispatch
			sock.sendTo( buf[0..bufLen], to );
		}
	}
	else {
		static void transmitOOB( Socket sock, Address to, ... ) {
			ubyte[PACKET_LENGTH]	buf;
			int						bufLen = 4;	// !!
			char[]					s;

			void putc( dchar c ) {
				buf[bufLen] = cast( ubyte )c;
				bufLen++;
			}

			// format args
			std.format.doFormat( &putc, _arguments, _argptr );

			// write the packet header
			*cast( int * )buf[0..4] = -1;

			// dispatch
			sock.sendTo( buf[0..bufLen], to );
		}
	}

	/**
		Sends a message to a remote host.
	*/
	void transmit( ubyte[] msg ) {
		if ( outgoingFragments ) {
			throw new Exception( "DnetChannel.transmit: unsent outgoing fragments" );
		}

		// fragment large messages
		if ( msg.length >= FRAGMENT_SIZE ) {
			outgoingFragments = true;
			outgoingFragmentOffset = 0;
			outgoingFragmentLength = msg.length;
			outgoingFragmentBuffer[0..outgoingFragmentLength] = msg[];

			// send the first fragment
			transmitNextFragment();
			return;
		}

		//
		// write the packet
		//

		ubyte[PACKET_LENGTH]	buf;
		DnetWriter				write;

		write.setContents( buf );

		// write the sequence
		write( outgoingSequence );

		// write the packet data
		write.putBytes( msg );

		// send the packet
		socket.sendTo( write.slice, remoteAddress );

		// increment outgoing sequence
		outgoingSequence++;
	}

	/**
		Transmits next fragment.
	*/
	void transmitNextFragment() {
		if ( !outgoingFragments ) {
			throw new Exception( "DnetChannel.transmitNextFragment: no unsent fragments" );
		}

		int						fragmentLength;
		ubyte[PACKET_LENGTH]	buf;
		DnetWriter				write;

		write.setContents( buf );

		if ( outgoingFragmentOffset + FRAGMENT_SIZE > outgoingFragmentLength ) {
			fragmentLength = outgoingFragmentLength - outgoingFragmentOffset;
		}
		else {
			fragmentLength = FRAGMENT_SIZE;
		}

		// write the packet header
		write( outgoingSequence | FRAGMENT_BIT );

		// write the fragment offset and length
		write( cast( ushort )outgoingFragmentOffset );
		write( cast( ushort )fragmentLength );

		// write the packet data
		write.putBytes( outgoingFragmentBuffer[outgoingFragmentOffset..outgoingFragmentOffset+fragmentLength] );
		outgoingFragmentOffset += fragmentLength;

		// send the packet
		socket.sendTo( write.slice, remoteAddress );

		if ( outgoingFragmentOffset == outgoingFragmentLength && fragmentLength != FRAGMENT_SIZE ) {
			outgoingFragments = false;
			outgoingSequence++;
		}
	}

	/**
		Decides whether a packet is correctly sequenced and therefore should be processed.
		Returns: buffer length if should be processed, 0 is returned otherwise.

		Note: buffer should be big enough to hold MESSAGE_LENGTH bytes.
	*/
	int process( ubyte[] packet, ubyte[] msg ) {
		uint		sequence;
		bool		fragmented;
		ushort		fragmentOffset, fragmentLength;
		DnetReader	read;
		DnetWriter	write;

		read.setContents( packet );
		write.setContents( msg );

		// read the sequence number
		read( sequence );

		// check for fragmented message
		if ( sequence & FRAGMENT_BIT ) {
			sequence &= ~FRAGMENT_BIT;
			fragmented = true;
		}

		// read the fragment offset and size if a fragmented message
		if ( fragmented ) {
			read( fragmentOffset );
			read( fragmentLength );
		}

		// discard out-of-order and duplicated packets
		if ( sequence <= incomingSequence ) {
			return 0;
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
				return 0;
			}

			// check if the fragment will fit into assembly buffer
			if ( incomingFragmentLength + fragmentLength > incomingFragmentBuffer.length ) {
				return 0;
			}

			// check if the fragment fits into packet
			if ( read.slice.length + fragmentLength > packet.length ) {
				return 0;
			}

			// check if the fragment is of correct size
			if ( fragmentLength > FRAGMENT_SIZE ) {
				return 0;
			}

			incomingFragmentBuffer[incomingFragmentLength..incomingFragmentLength+fragmentLength] = read.getBytes( fragmentLength );
			incomingFragmentLength += fragmentLength;

			// if this wasn't the last fragment, don't process anything
			if ( fragmentLength == FRAGMENT_SIZE ) {
				return 0;
			}

			// copy the fragment buffer to the message
			write.putBytes( incomingFragmentBuffer[0..incomingFragmentLength] );
		}
		else {
			// copy the packet to the message
			write.putBytes( read.getBytes( packet.length - read.slice.length ) );
		}

		incomingSequence = sequence;

		return write.slice.length;
	}

	package {
		Socket	socket;
		Address	remoteAddress;

		int		dropCount;						// the number of packets dropped
												// between current and previous

		// Sequence numbers.
		uint	incomingSequence;
		uint	outgoingSequence;

		// Incoming fragment buffer.
		uint	incomingFragmentSequence;
		uint	incomingFragmentLength;
		ubyte	incomingFragmentBuffer[MESSAGE_LENGTH];

		// Outgoing fragment buffer.
		bool	outgoingFragments;
		uint	outgoingFragmentOffset;
		uint	outgoingFragmentLength;
		ubyte	outgoingFragmentBuffer[MESSAGE_LENGTH];
	}
}
