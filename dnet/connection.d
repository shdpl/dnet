/**
	Copyright: (c) 2007 DNet Team
	Authors: DNet Team, see AUTHORS file
	License: MIT-style, see LICENSE file
*/
module dnet.connection;

version ( Tango ) {
	import tango.text.convert.Sprint;
}
else {
	import std.format;
}

import dnet.buffer;
import dnet.channel;
import dnet.socket;
import dnet.utils;
import dnet.time;
import dnet.protocol;
import dnet.host;
import dnet.fifo;

/**
	Simple name for two-end points connection, where one is always local address.
*/
class DnetConnection {
	package {
		// Connection state
		enum State {
			DISCONNECTED,		// not at all connected
			CHALLENGING,		// sending challenge request
			CONNECTING,			// received challenge request, sending connection request
			CONNECTED,			// got connection response, data can now be sent reliably
			DISCONNECTING,		// disconnecting
		}

		// Generic payload
		struct Payload {
			enum Type : ubyte {
				BAD,		// this one's bad
				DATA,		// this one's data
				CMD			// and this one is a command
			}

			Type		payloadType;
			ubyte[]		data;

			void archive( T )( ref T arch ) {
				arch( cast( ubyte )payloadType );
				arch( data );
			}
		}

		alias DnetFifo!( Payload, 64 )	PayloadFifo;
		alias DnetFifo!( ubyte[], 64 )	DataFifo;
		alias DnetFifo!( char[], 64 )	CmdFifo;
		const RELIABLE_BACKUP			= 64;
		const MESSAGE_BACKUP			= 32;
		const MESSAGE_BACKUP_MASK		= MESSAGE_BACKUP - 1;

		// protocol bytes
		enum CmdBytes {
			BAD,
			RELIABLE,
			UNRELIABLE,
			EOM
		}

		// message info
		struct MsgInfo {
			int		size;					// message length
			int		sentTime;				// time we sent a message
			int		ackTime;				// time we got a response
		}

		State		state;
		DnetHost	host;					// our host
		DnetChannel	channel;				// channel used for communications
		bool		local;					// is this a local or a foreign connection?

		// connection information
		Address		remoteAddress;			// site we're connecting to
		Address		publicAdr;				// our address as translated by a NAT
		uint		challengeNumber;		// challenge number
		int			connectionRetransmit;	// last connection packet dispatch time
		int			connectionAttempts;		// how many times we have sent connection packet
		char[]		userInfo;				// reference to user info

		// flow control
		int			uploadRateMax;			// maximum upload bandwidth (set by host)
		int			downloadRateMax;		// maximum download bandwidth (set by remote side)

		// data queues
		PayloadFifo	sendQueue;				// outgoing payload
		DataFifo	receiveQueue;			// received data
		CmdFifo		cmdQueue;				// received commands
		Payload[]	reliableQueue;
		int			reliableSequence;

		uint		outgoingAcknowledge;	// last outgoingSequence the remote side has received. This comes in
											// handy when it gets to calculating pings and delta-compressing the messages
		uint		reliableAcknowledge;	// last acknowledged reliable message
		uint		lastReliableSequence;	// last received reliable sequence. This is reliableAcknowledge on the	
											// remote side. It is also needed to detect reliable data loss and to
											// filter duplicated reliable data, which can occur in case of a lossy
											// connection

		MsgInfo[MESSAGE_BACKUP]	messages;
		int			latencyValue;

		// timers
		int			disconnectTime;		// time we started disconnection process
		int			lastReceive;		// time the last packet has been received
		int			lastTransmit;		// time the last packet has been sent
		int			packetTime;			// time the next packet should be sent
	}

	/// User data. Use it to store application-specific data. Note: Members are placed into an anonymous union.
	struct UserData {
		union {
			Object	obj;				/// object reference
			void *	ptr;				/// POD reference
		}
	}

	UserData	userData;				/// Reference to user data.

	/**
		Constructor.
	*/
	package this( DnetHost host, bool local ) {
		this.host = host;
		this.local = local;

		// init data queues
		sendQueue.init();
		receiveQueue.init();
		cmdQueue.init();
		reliableQueue.length = RELIABLE_BACKUP;
	}

	/**
		Buffers data for sending. Set reliable to true if you want the data
		retransmitted in case of loss. data may not be greater than MESSAGE_LENGTH.

		Note: data is copied, not referenced to.
	*/
	void send( ubyte[] data, bool reliable = false ) {
		sendPayload( data, reliable, Payload.Type.DATA );
	}

	/**
		Buffers a command for sending.
	*/
	void sendCommand( char[] cmd, bool reliable = true ) {
		sendPayload( cmd, reliable, Payload.Type.CMD );
	}

	/**
		Reads next received data. data must be big enough to hold MESSAGE_LENGTH bytes.
		Returns: number of bytes written into data, 0 if _receive queue is empty.
	*/
	int receive( ubyte[] data ) {
		ubyte[]	s;

		if ( !receiveQueue.get( s ) ) {
			return 0;
		}

		int len = s.length;
		data[0..len] = s[];
		host.allocator.free( s );
		return len;
	}

	/**
		Reads next received command.
		Returns: number of bytes written into cmd, 0 if commands queue is empty.
	*/
	private int receiveCommand( char[] cmd ) {
		char[]	s;

		if ( !cmdQueue.get( s ) ) {
			return 0;
		}

		int len = s.length;
		cmd[0..len] = s[];
		host.allocator.free( s );
		return len;
	}

	/**
		Disconnect from the server currently connected to.
	*/
	void disconnect( char[] reason ) {
		if ( state < State.CONNECTED ) {
			return;
		}

		if ( state == State.DISCONNECTING ) {
			return;
		}

		state = State.DISCONNECTING;
		disconnectTime = currentTime();

		if ( local && host.disconnection ) {
			host.disconnection( this, "disconnected" );
		}

		version ( Tango ) {
			scope sprint = new Sprint!( char )( 1024 );
			sendCommand( sprint( "disconnect \"{0}\"", reason ) );
		}
		else {
			char[1024]	buf;
			sendCommand( sformat( buf, "disconnect \"%s\"", reason ) );
		}
	}

	/**
		Returns true if _connected, false is returned otherwise.
	*/
	bool connected() {
		return ( state >= State.CONNECTED ) ? true : false;
	}

	/**
		Returns estimated network _latency, in ms.
	*/
	int latency() {
		return latencyValue;
	}

	/**
		Returns estimated packet loss ratio.
	*/
	float lossRatio() {
		if ( !channel.receivedCount ) {
			return 0.0f;
		}
		return cast( float )channel.lostCount / cast( float )channel.receivedCount;
	}

	/**
		Returns true if connection was initiated locally, false is returned otherwise.
	*/
	bool isLocal() {
		return local;
	}

	/**
		Returns 'public' address if connection was initiated locally, otherwise returns 'local' address.
	*/
	Address publicAddress() {
		return publicAdr;
	}

	/**
		Buffers payload for sending. payloadType distinguishes between _data and a command.
	*/
	private void sendPayload( void[] data, bool reliable, Payload.Type payloadType ) {
		assert( data !is null );
		assert( data.length < MESSAGE_LENGTH );

		auto tmp = host.allocator.duplicate( cast( ubyte[] )data );

		if ( reliable ) {
			// if we would be losing a reliable data that hasn't been acknowledged,
			// we must drop the connection
			if ( reliableSequence - reliableAcknowledge == reliableQueue.length + 1 ) {
				disconnect( "irrecoverable loss of reliable data" );
				return;
			}

			reliableSequence++;
			auto index = reliableSequence & ( reliableQueue.length - 1 );

			if ( reliableQueue[index].data !is null ) {
				host.allocator.free( reliableQueue[index].data );
			}
			reliableQueue[index].payloadType = payloadType;
			reliableQueue[index].data = tmp;
		}
		else {
			Payload	payload;

			payload.payloadType = payloadType;
			payload.data = tmp;

			sendQueue.put( payload );
		}
	}

	/**
		Puts payload data into appropriate queue.
	*/
	private void receivePayload( void[] tmp, Payload.Type type ) {
		if ( type == Payload.Type.CMD ) {
			cmdQueue.put( cast( char[] )tmp );
		}
		else if ( type == Payload.Type.DATA ) {
			receiveQueue.put( cast( ubyte[] )tmp );
		}
		else {
			error( "bad payload type" );
		}
	}

	/**
		Throws an exception.
	*/
	private void error( char[] text ) {
		throw new Exception( text );
	}

	/**
		Throws an exception if expr is false.
	*/
	private void verify( bool expr, char[] text ) {
		if ( !expr ) {
			error( text );
		}
	}

	/*
		Connect _to server (listening host).

		See_Also: DnetHost.connect
		Note: userInfo is not copied, but referenced _to.
	*/
	package void connect( char[] to, ushort port, char[] userInfo ) {
		// set remote address
		remoteAddress = new IPv4Address( to, port );
		this.userInfo = userInfo;

		state = State.CHALLENGING;			// disconnected->challenging
		connectionAttempts = 0;
		connectionRetransmit = -9999;		// challenge request will be sent immediately
	}

	/*
		Sets up the connection. After that data can be delivered reliably.
	*/
	package void setup( Address from, int downloadRate, char[] publicAddressHost, ushort publicAddressPort ) {
		{
			auto a = cast( IPv4Address )from;
			assert( a !is null );
			channel.setup( host.socket, new IPv4Address( a.addr, a.port ) );
		}

		assert( downloadRate );
		downloadRateMax = downloadRate;
		userInfo = null;
		state = State.CONNECTED;

		lastReceive = currentTime();
		lastTransmit = 0;
		packetTime = 0;
		messages[] = messages.init;

		reliableSequence = 0;

		outgoingAcknowledge = 0;
		reliableAcknowledge = 0;
		lastReliableSequence = 0;

		publicAdr = new IPv4Address( publicAddressHost, publicAddressPort );

		// notify user
		if ( host.connection !is null ) {
			host.connection( this );
		}
	}

	/*
		Checks if disconnection has completed or connection got timed out.
	*/
	package void checkTimeOut( int dropPoint, int disconnectPoint ) {
		if ( state < State.CONNECTED ) {
			return;
		}

		if ( state == State.DISCONNECTING && disconnectTime < disconnectPoint ) {
			state = State.DISCONNECTED;
			return;
		}

		if ( lastReceive < dropPoint ) {
			state = State.DISCONNECTED;
			if ( host.disconnection !is null ) {
				host.disconnection( this, "connection timed out" );
			}
		}
	}

	/*
		Reads a packet. Called by host.
	*/
	package void readPacket( ubyte[] packet ) {
		if ( state < State.CONNECTED ) {
			return;
		}

		ubyte[MESSAGE_LENGTH]	msg;
		int len = channel.process( packet, msg );
		if ( !len ) {
			return;
		}

		// parse message if not in process of disconnection
		if ( state < State.DISCONNECTING ) {
			parseMessage( msg[0..len] );
		}

		// mark time we got a packet
		lastReceive = currentTime();
	}

	/*
		Dispatches a packet.
	*/
	package void transmit() {
		if ( state == State.DISCONNECTED ) {
			return;
		}

		// transmit connection requests
		if ( state < State.CONNECTED ) {
			transmitConnectionRequest();
			return;
		}

		if ( packetTime >= currentTime() ) {
			return;		// it's not time yet
		}

		int sequence;

		// if there are unsent fragments, send them now
		if ( channel.outgoingFragments ) {
			sequence = channel.outgoingSequence & MESSAGE_BACKUP_MASK;
			channel.transmitNextFragment();
		}
		else {
			// generate new message and send it
			if ( host.messageSend !is null ) {
				host.messageSend( this );
			}
			sendMessage();
			sequence = channel.outgoingSequence & MESSAGE_BACKUP_MASK;
			calculateLatency();
		}

		// schedule next dispatch
		packetTime = currentTime() + rateMsec( messages[sequence].size );

		// mark time we sent a packet
		lastTransmit = currentTime();
	}

	/**
		Returns time the packet of given size is supposed to take to send, based on upload bandwidth.
	*/
	private int rateMsec( int messageSize ) {
		int	packetSize = ( messageSize >= PACKET_LENGTH ) ? PACKET_LENGTH : messageSize;
		packetSize += 48;		// add some overhead

		// convert bits per second into bytes per seconds
		auto bps = uploadRateMax << 3;

		// figure out time it will take to send
		auto time = cast( float )packetSize / cast( float )bps;

		// return time in milliseconds
		return cast( int )( time * 1000 );
	}

	/**
		Executes commands that have been received this frame.
	*/
	private void executeCommands() {
		char[][MAX_COMMAND_ARGS]args;
		int						argCount;
		char[MESSAGE_LENGTH]	cmd;

		while ( true ) {
			auto l = receiveCommand( cmd );
			if ( !l ) {
				break;
			}
			argCount = splitIntoTokens( cmd[0..l], args );

			switch ( args[0] ) {
				// remote side disconnects
				case "disconnect":
					disconnect_f( args[0..argCount] );
					break;
/*				// bandwidth adjustment
				case "bw":
					verify( argCount == 3, "bw: bad args" );
					downloadMax = dnetAtoi( args[1] );
					uploadMax = dnetAtoi( args[2] );
					host.allocateBandwidth();
					break;*/
				default:
					if ( host.command !is null ) {
						host.command( this, cmd[0..l], args[0..argCount] );
					}
					break;
			}
		}
	}

	/**
		Aggregates data to be delivered into message and sends it.
	*/
	private void sendMessage() {
		ubyte[MESSAGE_LENGTH]	msg;
		DnetWriter				write;

		write.setContents( msg );

		write( channel.incomingSequence );
		write( lastReliableSequence );

		// write reliable payload
		writeReliablePayload( write );

		// write unreliable payload
		writeUnreliablePayload( write );

		// write end-of-message mark
		writeEOM( write );

		// check for overflow
		if ( write.overflowed ) {
			write.clear();
		}

		// dispatch message
		channel.transmit( write.slice );

		// save off message info in message history
		with ( messages[channel.outgoingSequence & MESSAGE_BACKUP_MASK] ) {
			sentTime = currentTime();
			ackTime = 0;
			size = write.slice.length;
		}
	}

	/**
		Writes reliable payload to a message.
	*/
	private void writeReliablePayload( ref DnetWriter write ) {
		write( cast( ubyte )CmdBytes.RELIABLE );
		write( cast( ubyte )( reliableSequence - reliableAcknowledge ) );

		for ( uint i = reliableAcknowledge + 1; i <= reliableSequence; i++ ) {
			write( i );
			reliableQueue[i & ( reliableQueue.length - 1 )].archive( write );
		}
	}

	/**
		Writes unreliable payload to a message.
	*/
	private void writeUnreliablePayload( ref DnetWriter write ) {
		Payload	payload;

		write( cast( ubyte )CmdBytes.UNRELIABLE );
		write( cast( ubyte )sendQueue.length );

		while ( sendQueue.get( payload ) ) {
			payload.archive( write );
			host.allocator.free( payload.data );
		}
	}

	/**
		Writes end-of-message mark to a message.
	*/
	private void writeEOM( ref DnetWriter write ) {
		write( cast( ubyte )CmdBytes.EOM );
	}

	/**
		Parses a message.
	*/
	private void parseMessage( ubyte[] msg ) {
		try {
			DnetReader	read;

			read.setContents( msg );

			read( outgoingAcknowledge );
			read( reliableAcknowledge );

			readReliablePayload( read );
			readUnreliablePayload( read );
			readEOM( read );

			// save off the time we got response
			messages[outgoingAcknowledge & MESSAGE_BACKUP_MASK].ackTime = currentTime();

			// fire 'receive' event
			if ( host.messageReceive !is null ) {
				host.messageReceive( this );
			}

			// execute commands
			executeCommands();
		}
		catch ( Exception e ) {
			disconnect( typeToUtf8( e ) );
		}
	}

	/**
		Reads reliable payload from message.
	*/
	private void readReliablePayload( ref DnetReader read ) {
		ubyte	cmd, count;
		uint	sequence;
		ubyte[]	s;
		Payload	payload;

		read( cmd );
		verify( cmd == CmdBytes.RELIABLE, "expected reliable" );

		read( count );

		for ( ubyte i = 0; i < count; i++ ) {
			read( sequence );
			payload.archive( read );

			if ( sequence < lastReliableSequence ) {
				continue;		// we have already received it
			}

			if ( sequence > lastReliableSequence + 1 ) {
				// we have lost some of the data, so drop the connection
				error( "lost some reliable data" );
			}

			lastReliableSequence = sequence;

			auto tmp = host.allocator.duplicate( payload.data );
			receivePayload( tmp, payload.payloadType );
		}
	}

	/**
		Reads unreliable payload from message.
	*/
	private void readUnreliablePayload( ref DnetReader read ) {
		ubyte	count, cmd;
		Payload	payload;

		read( cmd );
		verify( cmd == CmdBytes.UNRELIABLE, "expected unreliable" );

		read( count );

		for ( ubyte i = 0; i < count; i++ ) {
			payload.archive( read );
			auto tmp = host.allocator.duplicate( payload.data );
			receivePayload( tmp, payload.payloadType );
		}
	}

	/**
		Reads end-of-message mark.
	*/
	private void readEOM( ref DnetReader read ) {
		ubyte	cmd;

		read( cmd );
		verify( cmd == CmdBytes.EOM, "malformed message" );
	}

	/**
		Calculates latency amount.
	*/
	private void calculateLatency() {
		int		count, total;

		foreach ( ref m; messages ) {
			if ( m.ackTime > 0 ) {
				total += ( m.ackTime - m.sentTime );
				count++;
			}
		}

		if ( !count ) {
			latencyValue = 0;
		}
		else {
			latencyValue = total / count;
		}
	}

	/**
		Sends a connection request if time.
	*/
	private void transmitConnectionRequest() {
		// send connection requests once in a second
		if ( currentTime() - connectionRetransmit < 1000 ) {
			return;		// time hasn't come yet
		}

		if ( connectionAttempts >= 5 ) {
			state = State.DISCONNECTED;
			if ( host.connectionRefused ) {
				host.connectionRefused( this, "connection refused" );
			}
			return;
		}

		switch ( state ) {
		case State.CHALLENGING:
			DnetChannel.transmitOOB( host.socket, remoteAddress, "challenge_request" );
			break;
		case State.CONNECTING:
			version ( Tango ) {
				DnetChannel.transmitOOB( host.socket, remoteAddress, "connection_request {0} {1} \"{2}\" {3}", PROTOCOL_VERSION, challengeNumber, userInfo, downloadRateMax );
			}
			else {
				DnetChannel.transmitOOB( host.socket, remoteAddress, "connection_request %d %d \"%s\" %d", PROTOCOL_VERSION, challengeNumber, userInfo, downloadRateMax );
			}
			break;
		}

		connectionRetransmit = currentTime();
		connectionAttempts++;
	}

	/*
		Processes OOB challenge response. Called by host.
	*/
	package void oobChallengeResponse( char[][] args, Address from ) {
		if ( state != State.CHALLENGING ) {
			if ( state == State.CONNECTING ) {
				debugPrint( "duplicate challenge received" );
			}
			else {
				debugPrint( "unwanted challenge received" );
			}
			return;
		}

		{
			auto a = cast( IPv4Address )from;
			auto b = cast( IPv4Address )remoteAddress;
			assert( a !is null && b !is null );

			if ( a.addr != b.addr || a.port != b.port ) {
				debugPrint( "challenge not from server" );
				return;
			}
		}

		if ( args.length != 2 ) {
			debugPrint( "malformed challenge received" );
			return;
		}

		challengeNumber = dnetAtoi( args[1] );

		state = State.CONNECTING;		// challenging -> connecting
		connectionAttempts = 0;
		connectionRetransmit = -9999;	// connection request will fire immediately
	}

	/*
		Processes OOB connection response. Called by host.
	*/
	package void oobConnectionResponse( char[][] args, Address from ) {
		if ( state != State.CONNECTING ) {
			if ( state == State.CONNECTED ) {
				debugPrint( "duplicate connection response received" );
			}
			else {
				debugPrint( "unwanted connection response received" );
			}
			return;
		}
		if ( args.length != 4 ) {
			debugPrint( "malformed connection response" );
			return;
		}
		setup( from, dnetAtoi( args[1] ), args[2], dnetAtoi( args[3] ) );
	}

	/**
		Processes a disconnect command.
	*/
	private void disconnect_f( char[][] args ) {
		state = State.DISCONNECTING;
		disconnectTime = currentTime();
		if ( host.disconnection !is null ) {
			host.disconnection( this, args[1] );
		}
	}
}
