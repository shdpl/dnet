/**
	Copyright: (c) 2007 DNet Team
	Authors: DNet Team, see AUTHORS file
	License: MIT-style, see LICENSE file

	DNet does not introduce any abstractions ontop network layer provided by a standard library.
	This module only encapsulates differences between Phobos and Tango socket interfaces.
	Howerver, Socket class is extended to incorporate network conditions simulation feature.
*/
module dnet.socket;

version ( Tango ) {
	public import tango.net.Socket;
}
else {
	public import std.socket;
	alias InternetAddress IPv4Address;

	version ( Windows ) {
		pragma(lib, "ws2_32.lib");
		pragma(lib, "wsock32.lib");
	}
}

import dnet.utils;
import dnet.channel : PACKET_LENGTH;
import dnet.time;

/**
	Extends Socket to include network conditions simulation.
*/
class DnetSocket : Socket {
	private {
		struct Packet {
			ubyte[PACKET_LENGTH]data;
			int					dataLen;
			int					sendTime = -1;
			bool				dup;
			Address				to;
		}

		Packet[64]	packets;
	}

	public {
		int		simLatency;				/// Simulated latency, in ms
		int		simJitter;				/// Simulated jitter, in ms
		float	simDuplicate = 0.0f;	/// Simulated packet duplication probability, in percent
		float	simLoss = 0.0f;			/// Simulated packet loss probability, in percent
	}

	invariant {
		assert( simLoss !is float.nan );
		assert( simLoss >= 0 && simLoss <= 1 );

		assert( simDuplicate !is float.nan );
		assert( simDuplicate >= 0 && simDuplicate <= 1 );

		assert( simLatency >= 0 && simLatency <= 9999 );
		assert( simJitter >= 0 && simJitter <= 9999 );
	}

	this( AddressFamily family, SocketType type, ProtocolType protocol, bool create=true ) {
		super( family, type, protocol, create );
		simLoss = 0.0f;
		simDuplicate = 0.0f;
	}

	/**
	*/
	override int sendTo( void[] buf, Address to ) {
		// simulate packet loss
		if ( simLoss > 0.0 ) {
			if ( dnetRandFloat() < simLoss ) {
				return 0;		// oops
			}
		}

		// simulate latency
		if ( simLatency || simJitter || simDuplicate > 0.0 ) {
			auto jitter = ( simJitter % 2 ) + ( dnetRand() & simJitter );
			auto dup = ( dnetRandFloat() < simDuplicate ) ? true : false;
			auto p = allocPacket();

			p.dataLen = buf.length;
			p.data[0..p.dataLen] = cast( ubyte[] )buf[];
			p.sendTime = currentTime() + simLatency + jitter;
			p.dup = dup;
			p.to = to;

			return 0;
		}

		return super.sendTo( buf, to );
	}

	/**
		Updates latency simulation.
	*/
	package void emit() {
		if ( !simLatency ) {
			return;
		}

		// send delayed packets
		foreach ( ref p; packets ) {
			if ( p.sendTime == -1 ) {
				continue;
			}

			if ( p.sendTime <= currentTime() ) {
				super.sendTo( p.data[0..p.dataLen], p.to );
				if ( p.dup ) {
					super.sendTo( p.data[0..p.dataLen], p.to );
				}
				freePacket( &p );
			}
		}
	}

	private Packet *allocPacket() {
		Packet *	p = &packets[0];

		for ( int i = 0; i < packets.length; i++, p++ ) {
			if ( p.sendTime == -1 ) {
				return p;
			}
		}

		// grab first one
		p = &packets[0];
		freePacket( p );
		return p;
	}

	private void freePacket( Packet *p ) {
		p.sendTime = -1;
		p.to = null;
	}
}
