﻿/**
	Copyright: (c) 2007 DNet Team
	Authors: DNet Team, see AUTHORS file
	License: MIT-style, see LICENSE file
*/
module dnet.host;

import dnet.channel;
import dnet.connection;
import dnet.utils;
import dnet.time;
import dnet.socket;
import dnet.protocol;
import dnet.memory;

/**
	A collection of connections.
	This can be a server or a client or a peer connected to multiple points, depending
	on parameters passed to constructor.

	Host is scalable enough to service up to 500 connections. It uses asynchronous
	IO running in a single thread. The rationale behind this solution is that much more
	scalable game server (>500 connections) will most likely be developed to run in a
	cluster. Authors deem they cannot implement a server-cluster architecture with
	synchronous IO and multithreading. This is due to lack of the appropriate hardware.
	BUT... maybe someday there will be DnetMassiveHost.

	Note: the number of concurrent connections is not bounded in any way.
*/
class DnetHost {
	package {
		class Challenge {
			this( Address addr ) {
				address	= addr;
				number	= dnetRand();
				time	= currentTime();
			}

			int		number;		// challenge number
			Address	address;	// address of the requesting side
			int		time;		// time when challenge was created
		}

		Challenge[char[]]		challenges;
		DnetConnection[char[]]	connections;
		DnetAllocator			allocator;		// packet memory allocator

		// communications
		Socket		socket;
		Address		from;
		bool		listen;

		// development tools
		float		lossRatio;	// percentage of simulated packet loss
	}

	/**
		Constructor.

		Parameters:
	
			localAddress = address to bind socket to, null means automatic address selection
	
			localPort = port to bind socket to, 0 means automatic port selection
	
			listen = set to false to disallow inbound connections
	*/
	this( char[] localAddress = null, ushort localPort = 0, bool listen = true ) {
		debugPrint( "DnetHost.this()" );

		this.listen = listen;
		this.lossRatio = 0.0f;

		// create a socket to be used for communications
		socket = new Socket( AddressFamily.INET, SocketType.DGRAM, ProtocolType.UDP );
		socket.blocking = false;
		version ( Tango ) {
			from = socket.newFamilyObject();
		}

		// bind socket to address
		if ( localAddress.length ) {
			socket.bind( new IPv4Address( localAddress, localPort ) );
		}
	}

	/**
		Initiates a connection to a remote side identified by address and port. userData
		will be delivered to remote side and passed to dnet.host.DnetHost.onConnectionRequest().
		It may not be longer than 1024 characters.

		Note: userData is not copied, but referenced to.
	*/
	DnetConnection connect( char[] address, ushort port, char[] userData = null ) {
		assert( userData.length < 1024 );
		debugPrint( "DnetHost.connectTo()" );

		auto c = new DnetConnection( this );
		c.connect( address, port, userData );

		connections[typeToUtf8( c.remoteAddress ).dup] = c;

		return c;
	}

	/**
		Sends and receives data.
	*/
	void emit() {
		ubyte[PACKET_LENGTH]			buf;
		char[][MAX_OOB_COMMAND_ARGS]	args;
		int								dropPoint = currentTime - 8000;
		int								disconnectPoint = currentTime - 3000;

		// send packets
		foreach ( c; connections ) {
			c.transmit();
			c.checkTimeOut( dropPoint, disconnectPoint );
		}

		// delete dead connections
		for ( auto i = 0; i < connections.values.length; i++ ) {
			auto c = connections.values[i];

			if ( c.state == DnetConnection.State.DISCONNECTED ) {
				debugPrint( "deleting dead connection" );
				connections.remove( typeToUtf8( c.channel.remoteAddress ) );
			}
		}

		// receive packets
		while ( true ) {
			int len = socket.receiveFrom( buf, from );
			if ( len <= 0 ) {
				break;
			}

			if ( len < 4 ) {
				continue;
			}
			
			// simulate packet loss
			if ( lossRatio > 0.0f ) {
				if ( dnetRandFloat() < lossRatio ) {
					continue;		// oops
				}
			}


			// process out-of-band messages
			if ( *cast( int * )buf.ptr == -1 ) {
				int count = splitIntoTokens( cast( char[] )( buf[4..len] ), args );
				processOutOfBand( args[0..count] );
				continue;
			}

			// process in-band messages
			processInBand( buf[0..len] );
		}
	}

	/**
		Sends data to all established connections.

		Note: data is copied, not referenced to.
	*/
	void broadcast( ubyte[] data, bool reliable = false ) {
		foreach ( c; connections.values ) {
			if ( c.state >= DnetConnection.State.CONNECTED ) {
				c.send( data, reliable );
			}
		}
	}

	/**
		Returns the list of connections.
	*/
	DnetConnection[char[]] getAll() {
		return connections;
	}

	/**
		Sets/gets simulated packet loss ratio, in percents.
	*/
	void simulatedLoss( float f ) {
		lossRatio = f;
		if ( lossRatio > 1.0f ) {
			lossRatio = 1.0f;
		}
		else if ( lossRatio < 0.0f ) {
			lossRatio = 0.0f;
		}
	}

	/**
		ditto
	*/
	float simulatedLoss() {
		return lossRatio;
	}

	/**
		Forcefully disconnect all established connections. There will be no connections after returning
		from this method.
	*/
	void disconnectAll() {
		foreach ( c; connections.values ) {
			c.disconnect();
		}

		emit();
		emit();
		emit();

		for ( int i = 0; i < connections.keys.length; i++ ) {
			connections.remove( connections.keys[i] );
		}
	}

	/**
		Called when connection request is processed to give user a chance to refuse connection.
		userData is the data passed to dnet.host.DnetHost.connectTo on the remote side.
		reason may hold the rejection text. It will be sent to the remote side.

		See_Also: dnet.host.DnetHost.connect

		Note: userData is located on stack.
	*/
	bool onConnectionRequest( Address from, char[] userData, ref char[] reason ) {
		return true;
	}

	/**
		Called when connection to the remote side has been established.
	*/
	void onConnectionResponse( DnetConnection c ) {

	}

	/**
		Called when c is being disconnected.
	*/
	void onDisconnect( DnetConnection c ) {

	}

	/**
		Called when unknown out-of-band packet is received. args hold the arguments.
		Return true if packet has been successfully processed, return false otherwise.
		NOTE: args are located on stack.
	*/
	bool onOOBpacket( char[][] args ) {
		return false;
	}

	/**
		Called when message from remote host has been received.
	*/
	void onMessage( char[] text ) {
		debugPrint( text );
	}

	/**
		Processes an out-of-band datagram.
	*/
	private void processOutOfBand( char[][] args ) {
		debugPrint( args[0] );

		switch ( args[0] ) {
			case "challenge_request":
				oobChallengeRequest( args );
				break;

			case "connection_request":
				oobConnectionRequest( args );
				break;

			case "challenge_response":
				oobChallengeResponse( args );
				break;

			case "connection_response":
				oobConnectionResponse( args );
				break;

			case "message":
				if ( args.length == 2 ) {
					onMessage( args[1] );
				}
				break;

			default:
				if ( !onOOBpacket( args ) ) {
					debugPrint( "unknow OOB command " ~ args[0] );
				}
				break;
		}
	}

	/**
		Processes an in-band datagram.
	*/
	private void processInBand( ubyte[] buf ) {
		if ( ( typeToUtf8( from ) in connections ) is null ) {
			return;		// malicious attack
		}
		connections[typeToUtf8( from )].readPacket( buf );
	}

	/**
		Processes OOB challenge request.
	*/
	private void oobChallengeRequest( char[][] args ) {
		// are we listening?
		if ( !listen ) {
			return;
		}

		// do we have a challenge for this address?
		if ( ( typeToUtf8( from ) in challenges ) is null ) {
			// we do not
			challenges[typeToUtf8( from )] = new Challenge( from );
		}

		// send it back
		version ( Tango ) {
			DnetChannel.transmitOOB( socket, from, "challenge_response {0}", challenges[typeToUtf8( from )].number );
		}
		else {
			DnetChannel.transmitOOB( socket, from, "challenge_response %d", challenges[typeToUtf8( from )].number );
		}
	}

	/**
		Processes OOB connection request.
	*/
	private void oobConnectionRequest( char[][] args ) {
		// are we listening?
		if ( !listen ) {
			return;
		}

		if ( args.length != 4 ) {
			DnetChannel.transmitOOB( socket, from, "message \"malformed connection request\"" );
			return;
		}

		int protoVer = dnetAtoi( args[1] );
		int challenge = dnetAtoi( args[2] );

		if ( protoVer != PROTOCOL_VERSION ) {
			DnetChannel.transmitOOB( socket, from, "message \"wrong DNet protocol version\"" );
			return;
		}

		if ( ( typeToUtf8( from ) in challenges ) is null || challenge != challenges[typeToUtf8( from )].number ) {
			DnetChannel.transmitOOB( socket, from, "message \"bad challenge\"" );
			return;
		}

		char[]	reason;

		// acknowledge the user of a new connection
		if ( !onConnectionRequest( from, args[3], reason ) ) {
			debugPrint( "connection rejected by user" );
			version ( Tango ) {
				DnetChannel.transmitOOB( socket, from, "message \"{0}\"", reason );
			}
			else {
				DnetChannel.transmitOOB( socket, from, "message \"%s\"", reason );
			}
			return;
		}

		// add the address to the list of connections if it isn't yet added
		if ( ( typeToUtf8( from ) in connections ) is null ) {
			connections[typeToUtf8( from )] = new DnetConnection( this );
		}
		else {
			// otherwise reuse already existing connection
		}

		connections[typeToUtf8( from )].setup( from );

		// send connection acknowledgement back to the remote host
		DnetChannel.transmitOOB( socket, from, "connection_response" );
	}

	/**
		Processes OOB challenge response.
	*/
	private void oobChallengeResponse( char[][] args ) {
		if ( ( typeToUtf8( from ) in connections ) is null ) {
			return;		// malicious attack
		}
		connections[typeToUtf8( from )].oobChallengeResponse( args, from );
	}

	/**
		Processes OOB connection response.
	*/
	private void oobConnectionResponse( char[][] args ) {
		if ( ( typeToUtf8( from ) in connections ) is null ) {
			return;		// malicious attack
		}
		connections[typeToUtf8( from )].oobConnectionResponse( args, from );
	}
}
