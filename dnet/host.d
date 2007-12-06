/**
	Copyright: (c) 2007 DNet Team
	Authors: DNet Team, see AUTHORS file
	License: MIT-style, see LICENSE file
*/
module dnet.host;

import tango.io.Stdout;

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
	IO running in main thread. The rationale behind this solution is that much more
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
				number	= dnetRand() & 0xFFFF;
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
		DnetSocket	socket;
		Address		from;
		char[]		localAdr;
		ushort		localPort;
		bool		listen;
	}

	public {
		int			uploadBw;		/// Available upload bandwidth, in bps
		int			downloadBw;		/// Available download bandwidth, in bps

		int			simLatency;				/// Simulated latency, in ms
		int			simJitter;				/// Simulated jitter, in ms
		float		simDuplicate = 0.0f;	/// Simulated packet duplication, probability in range [0, 1]
		float		simLoss = 0.0f;			/// Simulated packet loss, probability in range [0, 1]

		/**
			Called when connection request is processed to give user a chance to refuse connection.
			userInfo is the data passed to DnetHost.connect on the remote side.
			reason may hold the rejection text which will be sent to the remote side.

			See_Also: DnetHost.connect

			Note: userInfo is located on stack.
		*/
		bool delegate( Address from, char[] userInfo, ref char[] reason ) connectionRequest;

		/**
			Called when connection to the remote side has been established.
		*/
		void delegate( DnetConnection c ) connection;

		/**
			Called when connection attempt has not succeeded.
		*/
		void delegate( DnetConnection c, char[] reason ) connectionRefused;

		/**
			Called when c is being disconnected.
		*/
		void delegate( DnetConnection c, char[] reason ) disconnection;

		/**
			Called on every unrecognised _command. args hold tokenized cmd.
		*/
		void delegate( DnetConnection c, char[] cmd, char[][] args ) command;

		/**
			Called when network has dealt with previous message and is ready to send a new one. Use this method as an
			entry point for sending unreliable data.
		*/
		void delegate( DnetConnection c ) messageSend;

		/**
			Called upon message arrival.
		*/
		void delegate( DnetConnection c ) messageReceive;

		/**
			Called when enumeration request is received. Return 0 if you don't want your host enumerated, else return
			number of bytes written into hostInfo.
		*/
		int delegate( char[] userInfo, char[] hostInfo ) enumerationRequest;

		/**
			Called when enumeration response is received.
		*/
		void delegate( char[] hostInfo, Address from ) enumerationResponse;
	}

	/**
		Constructor.

		Parameters:

			uploadBw = available upload bandwidth, in bits per second. May not be set to zero.

			downloadBw = available download bandwidth, in bits per second. May not be set to zero.

			localAddress = address to bind socket to, null means automatic address selection

			localPort = port to bind socket to, 0 means automatic port selection

			listen = set to false to disallow inbound connections
	*/
	this( int uploadBw, int downloadBw, char[] localAddress = "localhost", ushort localPort = 0, bool listen = true )
	in {
		assert( uploadBw );
		assert( downloadBw );
	}
	body {
		debugPrint( "DnetHost.this()" );

		this.uploadBw = uploadBw;
		this.downloadBw = downloadBw;
		this.listen = listen;

		// create a socket to be used for communications
		socket = new DnetSocket( AddressFamily.INET, SocketType.DGRAM, ProtocolType.UDP );
		socket.blocking = false;
		version ( Tango ) {
			from = socket.newFamilyObject();
		}

		// make it broadcast capable
		try {
			uint[1]	value = 1;
			socket.setOption( SocketOptionLevel.SOCKET, SocketOption.SO_BROADCAST, value );
		}
		catch ( Exception e ) {
			debugPrint( "DnetHost.this(): " ~ typeToUtf8( e ) );
		}

		// bind socket to address
		if ( localAddress.length ) {
			socket.bind( new IPv4Address( localAddress, localPort ) );
		}
		else {
			socket.bind( new IPv4Address( "localhost" ) );
		}

		auto a = cast( IPv4Address )socket.localAddress;
		assert( a !is null );

		this.localAdr = a.toAddrString;
		this.localPort = a.port;
	}

	/**
		Initiates a connection to a remote side identified by address and port. userInfo
		will be delivered to remote side and passed to $(D_PSYMBOL connectionRequest).
		It may not be longer than 1024 characters.
		Returns created connection.

		Note: userInfo is not copied, but referenced to.
	*/
	DnetConnection connect( char[] address, ushort port, char[] userInfo = null ) {
		assert( userInfo.length < 1024 );
		debugPrint( "DnetHost.connectTo()" );

		auto c = new DnetConnection( this, true );
		c.connect( address, port, userInfo );
		connections[typeToUtf8( c.remoteAddress ).dup] = c;

		c.downloadRateMax = downloadBw / connections.values.length;

		return c;
	}

	/**
		Sends and receives data.
	*/
	void emit() {
		// update latency simulation
		socket.simLatency = simLatency;
		socket.simJitter = simJitter;
		socket.simDuplicate = simDuplicate;
		socket.simLoss = simLoss;
		socket.emit();

		ubyte[PACKET_LENGTH]	buf;
		char[][MAX_COMMAND_ARGS]args;
		int						dropPoint = currentTime - 8000;
		int						disconnectPoint = currentTime - 3000;

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

		// allocate bandwidth
		allocateBandwidth();

		// receive packets
		while ( true ) {
			int len = socket.receiveFrom( buf, from );
			if ( len <= 0 ) {
				break;
			}

			if ( len < 4 ) {
				continue;
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
		Sends command to all established connections.
	*/
	void broadcastCommand( char[] cmd, bool reliable = true ) {
		foreach ( c; connections.values ) {
			if ( c.state >= DnetConnection.State.CONNECTED ) {
				c.sendCommand( cmd, reliable );
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
		Forcefully disconnect all established connections. There will be no connections after returning
		from this method.
	*/
	void disconnectAll( char[] reason = "host is shutting down" ) {
		foreach ( c; connections.values ) {
			c.disconnect( reason );
		}

		emit();
		emit();
		emit();

		for ( int i = 0; i < connections.keys.length; i++ ) {
			connections.remove( connections.keys[i] );
		}
	}

	/**
		Starts host enumeration by broadcasting packet containing userInfo. Enumeration requests will trigger
		enumerationRequest event on a remote host. It may reply and thus issue enumerationResponse on local host.
	*/
	void enumerateHosts( char[] userInfo, Address broadcastAddress ) {
		version ( Tango ) {
			DnetChannel.transmitOOB( socket, broadcastAddress, "enumerationRequest {0} \"{1}\"", PROTOCOL_VERSION, userInfo );
		}
		else {
			DnetChannel.transmitOOB( socket, broadcastAddress, "enumerationRequest %d \"%s\"", PROTOCOL_VERSION, userInfo );
		}
	}

	/**
		Allocates bandwidth between connections.
	*/
	private void allocateBandwidth() {
		// uniformly distribute bandwidth between connections
		// TODO: take bandwidth capacities heterogenity into account
		auto max = 0;
		if ( connections.values.length ) {
			max = uploadBw / connections.values.length;
		}
		else {
			max = uploadBw;
		}
		foreach ( c; connections.values ) {
			c.uploadRateMax = max;
		}
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

			case "connection_refused":
				oobConnectionRefused( args );
				break;

			case "enumerationRequest":
				oobEnumerationRequest( args );
				break;

			case "enumerationResponse":
				oobEnumerationResponse( args );
				break;

			default:
				debugPrint( "unknow OOB command " ~ args[0] );
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

		Processes OOB enumeration request.
	*/
	private void oobEnumerationRequest( char[][] args ) {
		if ( enumerationRequest is null ) {
			return;
		}

		if ( args.length != 3 ) {
			return;
		}

		auto protoVer = dnetAtoi( args[1] );
		auto userInfo = args[2];

		if ( protoVer != PROTOCOL_VERSION ) {
			return;
		}

		char[1024]	hostInfo;
		auto len = enumerationRequest( userInfo, hostInfo );
		if ( len ) {
			version ( Tango ) {
				DnetChannel.transmitOOB( socket, from, "enumerationResponse \"{0}\"", hostInfo[0..len] );
			}
			else {
				DnetChannel.transmitOOB( socket, from, "enumerationResponse \"%s\"", hostInfo[0..len] );
			}
		}
	}

	/**
		Processes OOB enumeration response.
	*/
	private void oobEnumerationResponse( char[][] args ) {
		if ( enumerationResponse is null ) {
			return;
		}
		if ( args.length != 2 ) {
			return;
		}
		enumerationResponse( args[1], from );
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

		if ( args.length != 5 ) {
			DnetChannel.transmitOOB( socket, from, "connection_refused \"malformed connection request\"" );
			return;
		}

		int protoVer = dnetAtoi( args[1] );
		int challenge = dnetAtoi( args[2] );
		char[] userInfo = args[3];
		int downloadRate = dnetAtoi( args[4] );

		if ( protoVer != PROTOCOL_VERSION ) {
			DnetChannel.transmitOOB( socket, from, "connection_refused \"wrong DNet protocol version\"" );
			return;
		}

		if ( ( typeToUtf8( from ) in challenges ) is null || challenge != challenges[typeToUtf8( from )].number ) {
			DnetChannel.transmitOOB( socket, from, "connection_refused \"bad challenge\"" );
			return;
		}

		char[]	reason;

		// acknowledge the user of a new connection
		if ( connectionRequest && !connectionRequest( from, userInfo, reason ) ) {
			debugPrint( "connection rejected by user" );
			version ( Tango ) {
				DnetChannel.transmitOOB( socket, from, "connection_refused \"{0}\"", reason );
			}
			else {
				DnetChannel.transmitOOB( socket, from, "connection_refused \"%s\"", reason );
			}
			return;
		}

		// add the address to the list of connections if it isn't yet added
		if ( ( typeToUtf8( from ) in connections ) is null ) {
			connections[typeToUtf8( from )] = new DnetConnection( this, false );
		}
		else {
			// otherwise reuse already existing connection
		}
		auto c = connections[typeToUtf8( from )];

		c.userInfo = userInfo;
		c.setup( from, downloadRate, localAdr, localPort );

		// send connection acknowledgement back to the remote host
		assert( c.downloadRateMax );
		auto a = cast( IPv4Address )from;
		assert( a !is null );
		version ( Tango ) {
			DnetChannel.transmitOOB( socket, from, "connection_response {0} \"{1}\" {2}", c.downloadRateMax, a.toAddrString, a.port );
		}
		else {
			DnetChannel.transmitOOB( socket, from, "connection_response %d \"%s\" %d", c.downloadRateMax, a.toAddrString, a.port );
		}
	}

	/**
		Processes OOB challenge response.
	*/
	private void oobChallengeResponse( char[][] args ) {
		if ( ( typeToUtf8( from ) in connections ) is null ) {
			return;		// malicious attack OR bug in dnet
		}
		connections[typeToUtf8( from )].oobChallengeResponse( args, from );
	}

	/**
		Processes OOB connection response.
	*/
	private void oobConnectionResponse( char[][] args ) {
		if ( ( typeToUtf8( from ) in connections ) is null ) {
			return;		// malicious attack OR bug in dnet
		}
		connections[typeToUtf8( from )].oobConnectionResponse( args, from );
	}

	/**
		Processes OOB 'connection refused' command.
	*/
	private void oobConnectionRefused( char[][] args ) {
		if ( ( typeToUtf8( from ) in connections ) is null ) {
			return;
		}
		auto text = ( args.length == 2 ) ? args[1] : null;
		auto c = connections[typeToUtf8( from )];

		c.state = DnetConnection.State.DISCONNECTED;
		if ( connectionRefused !is null ) {
			connectionRefused( c, text );
		}
	}
}
