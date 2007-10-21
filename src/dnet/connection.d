/*

Copyright (c) 2007 Branimir Milosavljevic <branimir.milosavljevic@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

module dnet.connection;

version ( Tango ) {
	private import tango.io.Stdout;
	private import tango.text.convert.Integer;
	private import tango.text.convert.Layout;
	private import tango.core.Vararg;
	private import tango.math.Random;
	private import tango.core.Exception;
	private import tango.util.time.Clock;

	private Layout!( char )	layout;

	static this() {
		layout = new Layout!( char );
	}
}
else {
	private import std.conv;
	private import std.stdarg;
	private import std.stdio;
	private import std.random;
	private import std.string;
	private import std.date;
	private import std.utf;
}

private import dnet.socket;
private import dnet.fifo;
private import dnet.buffer;
private import dnet.utils;

private import dnet.internal.flowinfo;
private import dnet.internal.protocol;
private import dnet.internal.window;

private const {
	int		PROTOCOL_VERSION	= 1;
}

version ( Tango ) {
	private void sendOOB( DnetSocket socket, DnetAddress to, char[] fmt, TypeInfo[] arguments, Arg argptr ) {
		char[PACKET_SIZE]	result;
		*cast( int * )result = -1;

		char[] s = layout.sprint( result[int.sizeof..$], fmt, arguments, argptr );
		socket.sendTo( result[0..s.length+int.sizeof], to );
	}
}
else {
	private void sendOOB( DnetSocket socket, DnetAddress to, TypeInfo[] arguments, va_list argptr ) {
		char[PACKET_SIZE]	s;
		*cast( int * )s = -1;

		size_t i = int.sizeof;

		void putc( dchar c ) {
			if ( c <= 0x7F ) {
				if ( i >= s.length ) {
					throw new Exception( "dnet.connection.DnetConnection.sendOOB" );
				}
				s[i] = cast( char )c;
				++i;
			}
			else {
				char[4] buf;
				char[] b;

				b = std.utf.toUTF8( buf, c );
				if ( i + b.length > s.length ) {
					throw new Exception( "dnet.connection.DnetConnection.sendOOB" );
				}
				s[i..i + b.length] = b[];
				i += b.length;
			}
		}

		std.format.doFormat( &putc, arguments, argptr );

		socket.sendTo( s[0..i], to );
	}
}

/*
packet header structure
-----------------------
31	sequence
1	fragment flag
32	reliable acknowledge
8	packet flags

CMD_BYTES.RELIABLE
ubyte count
count times {
	ushort	length
	ubyte[]	data
}
CMD_BYTES.UNRELIABLE
ubyte[] data
-----------------------
Reliable data is queued, then passed to the remote side. It will be retransmitted until
remote side acknowledges of the delivery. DnetConnection will try to combine multiple
small chunks of reliable data into a bigger one. Unreliable data will be appended
to the packet if there's enough space left.
*/

/**
	Simple name for two-end points connection, where one is allways local address.
	Remote address' port *might* not be the same after receiving response.
	It is because other side might spawn new socket to communicate with calling side.
*/
public class DnetConnection {

	private {
		const int RELIABLE_BACKUP		= 64;	// Size of the reliable send queue.

		// connection state
		enum STATE {
			DISCONNECTED,		// not at all connected
			CHALLENGING,		// sending challenge request
			CONNECTING,			// received challenge request, sending connection request
			CONNECTED,			// got connection response, data can now be sent reliably
			DISCONNECTING,		// sending packets with Flags.Disconnecting
		}

		// packet flags
		enum Flags {
			Disconnecting	= ( 1 << 0 ),	// remote side is disconnecting
		}

		// protocol command bytes
		enum CMD_BYTES {
			BAD,
			RELIABLE,
			UNRELIABLE,
		}

		DnetSocket	socket;					// socket used for communications

		// connection information
		STATE		state;					// state of the connection
		uint		challengeNumber;		// challenge number we got from server
		DnetAddress	remoteAddress;			// address of the server
		DnetAddress	publicAddress;			// local address as translated by a NAT
		char[]		userData;				// user data passed in connectTo()
		long		lastReceive;			// time the last packet has been received
		long		lastTransmit;			// time the last packet has been sent

		Protocol	protocol;				// dispatches packets
		FlowInfo	flowInfo;				// stores flow control information

		// data buffers
		DnetFifo	sendQueue, receiveQueue;
		DnetWindow	reliableWindow;

		int			outgoingAcknowledge;	// last outgoingSequence the remote side has
											// received
											// this comes in handy when it gets to calculating
											// pings and delta-compressing the messages
		int			reliableAcknowledge;	// last acknowledged reliable message
		int			lastReliableSequence;	// last received reliable sequence
											// this is reliableAcknowledge on the remote side
											// it is also needed to detect reliable data loss
											// and to filter duplicated reliable data, which
											// can occur in case of a lossy connection
	}

	/**
		Constructor.
		Parameters:
		socket specifies _socket to use for communications.
		bandwidth specifies amount of downstream _bandwidth available, in bps.
		bandwidth defaults to 28.8Kbps.
	*/
	this( DnetSocket socket = null, int bandwidth = 28000 ) {
		if ( socket !is null ) {
			this.socket = socket;
		}
		else {
			this.socket = new DnetSocket();
		}

		sendQueue = DnetFifo();
		reliableWindow = DnetWindow( RELIABLE_BACKUP );
		receiveQueue = DnetFifo();

		flowInfo.availableBandwidth = bandwidth;
	}

	private void setup( DnetAddress theRemoteAddress, DnetAddress thePublicAddress ) {
		remoteAddress = theRemoteAddress;
		publicAddress = thePublicAddress;

		outgoingAcknowledge	= outgoingAcknowledge.init;
		lastReliableSequence = lastReliableSequence.init;
		reliableAcknowledge = reliableAcknowledge.init;

		protocol.clear();
		reliableWindow.clear();
		flowInfo.reset();

		state = STATE.CONNECTED;

		lastReceive = getUTCtime();
	}

	/**
		Disconnect from the server currently connected to.
	*/
	final public void disconnect() {
		if ( state < STATE.CONNECTED ) {
			return;		// not connected
		}

		state = STATE.DISCONNECTING;	// connected -> disconnecting

		transmit( true );
		transmit( true );

		onDisconnect();

		state = STATE.DISCONNECTED;		// disconnecting -> disconnected
	}

	/**
		Connect to server (listening collection). If already connected, will disconnect
		and then connect again.
		Throws an UtfException if theUserData is not a valid UTF8 string.
		theUserData may not be longer than 1024 characters.
	*/
	final public void connectTo( DnetAddress theRemoteAddress, char[] theUserData = null, DnetAddress theLocalAddress = null )
	in {
		version ( Tango ) {
			// TODO
		}
		else {
			std.utf.validate( theUserData );
		}
		assert( theUserData.length <= 1024 );
	}
	body {
		// disconnect from the server currently connected to
		disconnect();

		// save off user-defined data
		if ( userData ) {
			delete userData;
		}
		userData = theUserData.dup;

		// set local address
		if ( theLocalAddress !is null ) {
			socket.bind( theLocalAddress );
		}

		// set remote address
		remoteAddress = theRemoteAddress;

		state = STATE.CHALLENGING;		// disconnected -> challenging
		lastTransmit = -9999;			// challenge request will be sent immediately
	}

	/**
		Returns true if _connected, elsewise returns false.
	*/
	final public bool connected() {
		if ( state >= STATE.CONNECTED ) {
			return true;
		}
		return false;
	}

	/**
		Returns the address the connection is set-up on.
	*/
	final public DnetAddress getLocalAddress(){
		return socket.getLocalAddress();
	}

	/**
		Returns the address the connection is connecting/connected to.
		null is returned if disconnected.
	*/
	final public DnetAddress getRemoteAddress(){
		if ( state == STATE.DISCONNECTED ) {
			return null;
		}
		return remoteAddress;
	}

	/**
		Returns latency value.
	*/
	final public int getLatency() {
		return flowInfo.networkLatency();
	}

	/**
		Sets/gets available _bandwidth, in bps.
	*/
	final public void bandwidth( int newBandwidth ) {
		flowInfo.availableBandwidth = newBandwidth;
	}

	/**
		ditto
	*/
	final public int bandwidth() {
		return flowInfo.availableBandwidth;
	}

	/**
		Returns true if the bandwidth won't be chocked by sending another message.
		Elsewise false is returned.
	*/
	final public bool readyToTransmit() {
		return flowInfo.readyToTransmit();
	}

	/**
		Buffers the data for sending. Set reliable to true if you want the buff
		retransmitted in case of loss.
		Throws: AssertException if not connected().
	*/
	final public void send( ubyte[] buff, bool reliable )
	in {
		// don't even try to send until you get connected
		assert( state >= STATE.CONNECTED );
		assert( buff.length < MESSAGE_SIZE );
	}
	body {
		if ( reliable ) {
			// if we would be losing a reliable data that hasn't been acknowledged,
			// we must drop the connection
			if ( reliableWindow.putSequence - reliableAcknowledge > RELIABLE_BACKUP ) {
				version ( Tango ) {
					Stdout( "irrecoverable loss of reliable data, disconnecting" ).newline;
				}
				else {
					writefln( "irrecoverable loss of reliable data, disconnecting" );
				}
				disconnect();
				return;
			}

			reliableWindow.put( buff );
		}
		else {
			sendQueue.put( buff.dup );
		}
	}


	/**
		Sends an out-of-band packet.
	*/
	version ( Tango ) {
		final public void sendOOB( DnetAddress to, char[] fmt, ... ) {
			.sendOOB( socket, to, fmt, _arguments, _argptr );
		}
	}
	else {
		final public void sendOOB( DnetAddress to, ... ) {
			.sendOOB( socket, to, _arguments, _argptr );
		}
	}

	/**
		Reads next received data.
	 */
	final public ubyte[] receive() {
		return receiveQueue.get();
	}

	/**
		Sends and receives data to other end.
	*/
	final public void emit() {
		if ( state == STATE.DISCONNECTED ) {
			return;
		}

		// receive
		PacketBuf			packetBuffer;
		auto				buff = DnetBuffer( packetBuffer );
		scope DnetAddress	addr;

		int size = socket.receiveFrom( buff, addr );
		while ( size > 0 ) {
			if ( size < 4 ) {
				// check for undersize packet
				version ( Tango ) {
					Stdout.format( "undersize packet from {}", addr ).newline;
				}
				else {
					writefln( "undersize packet from %s", addr );
				}
				size = socket.receiveFrom( buff, addr );
				continue;
			}

			if ( *cast( int * )buff.getBuffer == -1 ) {
				// check out-of-band packets first
				processOutOfBand( buff, addr );
			}
			else {
				processInBand( buff, addr );
			}

			// get next packet
			size = socket.receiveFrom( buff, addr );
		}

		// check for time-out
		if ( state >= STATE.CONNECTED ) {
			long	dropPoint = getUTCtime() - 8000;
			if ( lastReceive < dropPoint ) {
				version ( Tango ) {
					Stdout( "connection timed-out" ).newline;
				}
				else {
					writefln( "connection timed-out" );
				}
				state = STATE.DISCONNECTED;
			}
		}

		transmit( false );

		flowInfo.calculateLatency();
	}

	/**
		Time in miliseconds since last receive event.
	*/
	final public long lastReceiveTime(){
		return lastReceive;
	}

	private void transmit( bool force ) {
		transmitConnectionRequest();

		// transmit in-band packets
		if ( state < STATE.CONNECTED ) {
			return;		// not yet connected
		}

		// don't transmit if time hasn't come
		// do transmit if force is true
		if ( !force && !flowInfo.readyToTransmit() ) {
			return;		// we would probably choke the bandwidth if we do
		}

		// transmit fragments of previous message,
		// if it was too large to send at once
		if ( protocol.hasUnsentFragments ) {
			protocol.dispatchNextFragment( socket, remoteAddress );
			return;
		}

		uint setPacketFlags() {
			uint	flags;

			if ( state == STATE.DISCONNECTING ) {
				// that's it, we're disconnecting
				flags |= Flags.Disconnecting;
			}

			return flags;
		}

		// set packet flags
		uint packetFlags = setPacketFlags();

		// write down message payload
		MsgBuf	msgBuffer = void;
		auto	msg = DnetBuffer( msgBuffer );

		writePayload( packetFlags, msg );

		// dispatch a packet
		protocol.dispatch( msg.getBuffer(), socket, remoteAddress );

		// mark the time
		lastTransmit = getUTCtime();

		// update data flow info
		flowInfo.dataSent( protocol.sequence, msg.length );
	}

	private void transmitConnectionRequest() {
		if ( state == STATE.CHALLENGING || state == STATE.CONNECTING ) {
			// send connection requests once in five seconds
			if ( getUTCtime() - lastTransmit < 5000 ) {
				return;	// time hasn't come yet
			}

			switch ( state ) {
				case STATE.CHALLENGING:
					sendOOB( remoteAddress, "challenge_request" );
					break;
				case STATE.CONNECTING:
					version ( Tango ) {
						sendOOB( remoteAddress, "connection_request {0} {1} \"{2}\"",
											PROTOCOL_VERSION, challengeNumber, userData );
					}
					else {
						sendOOB( remoteAddress, "connection_request %d %d \"%s\"",
											PROTOCOL_VERSION, challengeNumber, userData );
					}
					break;
			}

			lastTransmit = getUTCtime();
		}
	}

	private void processInBand( DnetBuffer buff, DnetAddress addr ) {
		void checkPacketFlags( uint flags ) {
			if ( flags & Flags.Disconnecting ) {
				// close the connection
				disconnect();
			}
		}

		// check in-bound packets
		// check unwanted packet
		if ( state < STATE.CONNECTED ) {
			version ( Tango ) {
				Stdout.format( "unwanted packet from {}", addr ).newline;
			}
			else {
				writefln( "unwanted packet from %s", addr );
			}
			return;
		}

		// check if the packet is not from the server
		if ( addr != remoteAddress ) {
			version ( Tango ) {
				Stdout.format( "packet not from server: {0} (should be {1})", addr, remoteAddress ).newline;
			}
			else {
				writefln( "packet not from server: %s (should be %s)", addr, remoteAddress );
			}
			return;
		}

		// mark time we last received a packet
		lastReceive = getUTCtime();

		if ( !protocol.process( buff ) ) {
			return;
		}

		uint	packetFlags;

		// read packet flags
		packetFlags = buff.readUbyte();

		// check packet flags
		checkPacketFlags( packetFlags );

		outgoingAcknowledge = buff.readInt();
		reliableAcknowledge = buff.readInt();

		// parse the packet
		parsePayload( buff );

//		writefln( "<-- %s %d %d", remoteAddress, reliableSequence, reliableAcknowledge );

		// update data flow info
		flowInfo.dataReceived( outgoingAcknowledge );
	}

	private void processOutOfBand( DnetBuffer buff, DnetAddress addr ) {
		char[]			cmd = cast( char[] )buff.getBuffer[int.sizeof..$];
		version ( Tango ) {
			// TODO
		}
		else {
			try {
				std.utf.validate( cmd );
			}
			catch ( UtfException e ) {
				writefln( "received invalid command: %s", e );
				return;
			}
		}
		scope char[][]	args = cmd.splitIntoTokens();

		switch ( args[0] ) {
			case "message":
				if ( args.length != 2 ) {
					version ( Tango ) {
						Stdout( "malformed message received" ).newline;
					}
					else {
						writefln( "malformed message received" );
					}
					break;
				}
				version ( Tango ) Stdout.format( "message: {}", args[1] ).newline;
				else writefln( "message: %s", args[1] );
				onMessage( args[1] );
				break;
			case "challenge_response":
				if ( state != STATE.CHALLENGING ) {
					if ( state == STATE.CONNECTING ) {
						version ( Tango ) {
							Stdout( "duplicate challenge received" ).newline;
						}
						else {
							writefln( "duplicate challenge received" );
						}
					}
					else {
						version ( Tango ) {
							Stdout( "unwanted challenge received" ).newline;
						}
						else {
							writefln( "unwanted challenge received" );
						}
					}
					break;
				}

				if ( addr != remoteAddress ) {
					version ( Tango ) {
						Stdout( "challenge not from server: {}", addr ).newline;
					}
					else {
						writefln( "challenge not from server: %s", addr );
					}
					break;
				}

				if ( args.length != 2 ) {
					version ( Tango ) {
						Stdout( "malformed challenge received" ).newline;
					}
					else {
						writefln( "malformed challenge received" );
					}
					break;
				}

				version ( Tango ) {
					challengeNumber = toInt!( char )( args[1] );
				}
				else {
					challengeNumber = toUint( args[1] );
				}

				state = STATE.CONNECTING;	// challenging -> connecting
				lastTransmit = -9999;		// connection request will fire immediately
				break;
			case "connection_response":
				if ( state != STATE.CONNECTING ) {
					if ( state == STATE.CONNECTED ) {
						version ( Tango ) {
							Stdout( "duplicate connection response received" ).newline;
						}
						else {
							writefln( "duplicate connection response received" );
						}
					}
					else {
						version ( Tango ) {
							Stdout( "unwanted connection response received" ).newline;
						}
						else {
							writefln( "unwanted connection response received" );
						}
					}
					break;
				}
				if ( args.length != 5 ) {
					version ( Tango ) {
						Stdout( "malformed connection response" ).newline;
					}
					else {
						writefln( "malformed connection response" );
					}
					break;
				}
				ushort	remotePort, publicPort;

				version ( Tango ) {
					try {
						remotePort = toInt!( char )( args[2] );
						publicPort = toInt!( char )( args[4] );
					}
					catch ( IllegalArgumentException e ) {
						Stdout.format( "bad connection response: {}", e ).newline;
					}
				}
				else {
					try {
						remotePort = toUshort( args[2] );
						publicPort = toUshort( args[4] );
					}
					catch ( ConvError e ) {
						writefln( "bad connection respose: %s", e );
						break;
					}
				}

				setup( new DnetAddress( args[1], remotePort ), new DnetAddress( args[3], publicPort ) );	// connecting -> connected
				break;
			default:
				if ( !onOOBpacket( args ) ) {
					version ( Tango ) {
						Stdout.format( "unrecognised OOB packet: {}", cmd ).newline;
					}
					else {
						writefln( "unrecognised OOB packet: %s", cmd );
					}
				}
				break;
		}
	}

	/**
		Writes down packet payload.
	*/
	private void writePayload( int flags, ref DnetBuffer buff ) {
		buff.putUbyte( flags );

		buff.putInt( outgoingAcknowledge );
		buff.putInt( lastReliableSequence );

		// write reliable data
		buff.putUbyte( CMD_BYTES.RELIABLE );

		buff.putUbyte( reliableWindow.putSequence - reliableAcknowledge );
		for ( size_t i = reliableAcknowledge + 1; i <= reliableWindow.putSequence; i++ ) {
			buff.putInt( i );
			buff.putString( reliableWindow.get( i ) );
		}

		// append unreliable data if there's space left
		buff.putUbyte( CMD_BYTES.UNRELIABLE );
		ubyte[] tmp = sendQueue.get();
		while ( tmp.length > 0 ) {
			if ( buff.length + tmp.length > buff.size ) {
				break;	// overflowed
			}

			buff.putData( tmp );
			tmp = sendQueue.get();
		}
	}

	/**
		Parses received packet payload.
	*/
	private void parsePayload( ref DnetBuffer buff ) {
		while ( true ) {
			ubyte	cmd = buff.readUbyte();
			if ( buff.isOverflowed ) {
				disconnect();
				break;
			}

			if ( cmd == CMD_BYTES.RELIABLE ) {
				size_t	count = buff.readUbyte();

				for ( size_t i = 0; i < count; i++ ) {
					int sequence = buff.readInt();
					ubyte[]	s = buff.readString();

					if ( sequence < lastReliableSequence ) {
						continue;		// we have already received it
					}

					if ( sequence > lastReliableSequence + 1 ) {
						// we have lost some of the data, so drop the connection
						version ( Tango ) Stdout( "lost some reliable data" ).newline;
						else writefln( "lost some reliable data" );
						disconnect();
						break;
					}

					lastReliableSequence = sequence;
					receiveQueue.put( s.dup );
				}
			}
			else if ( cmd == CMD_BYTES.UNRELIABLE ) {
				receiveQueue.put( buff.getBuffer[buff.bytesRead..$].dup );
				break;
			}
			else {
				disconnect();
				break;
			}
		}
	}

	/**
	*/
	public void onDisconnect() {

	}

	/**
	*/
	public void onMessage( char[] msg ) {

	}

	/**
	*/
	public bool onOOBpacket( char[][] args ) {
		return false;
	}
}

/**
	A collection of connections.
	This can be a server if you bind socket and listen 
	or it can be a client connected to multiple points.

	Collection is scalable enough to service up to 500 connections. It uses a single non-blocking
	socket running in a single thread. The rationale behind this solution is that much more
	scalable game server (>500 connections) will most likely be developed to run in a
	cluster. Authors deem they cannot implement a server-cluster architecture with
	synchronous IO and multithreading. This is due to lack of the appropriate hardware.
	BUT... maybe someday there will be DnetMassiveCollection.

	NOTE: the number of concurrent connections is not bounded in any way.
	TODO: make use of socket sets.
*/
public class DnetCollection {

	private {
		class Challenge {
			this( DnetAddress addr ) {
				address	= addr;
				version ( Tango ) {
					number	= Random.shared.next(8192);
					time	= Clock.now();
				}
				else {
					number	= rand();
					time	= getUTCtime();
				}
			}

			version ( Tango ) {
				char[] toUtf8() {
					return .toUtf8( number );
				}
			}
			else {
				char[] toString() {
					return format( "%d", number );
				}
			}

			uint			number;		// challenge number
			DnetAddress		address;	// address of the requesting side
			long			time;		// time when challenge was created
		}

		Challenge[char[]]		challenges;

		DnetSocket				loginSocket;	// used to listen for connection requests
		DnetSocket				inbandSocket;
		DnetConnection[char[]]	connections;
	}

	/**
		address is the _address to which login requests should be sent.
		inbandAddress denotes _address to which in-band packets should be sent.
	*/
	this( DnetAddress address, DnetAddress inbandAddress )
	in {
		assert( address !is null );
		assert( inbandAddress !is null );
	}
	body {
		loginSocket = new DnetSocket();
		inbandSocket = new DnetSocket();

		loginSocket.bind( address );
		inbandSocket.bind( inbandAddress );
	}

	/**
	*/
	final public DnetAddress getLocalAddress(){
		return loginSocket.getLocalAddress();
	}

	private void add( DnetAddress address ) {
		// we could spawn a new socket here...
		// but for now, we'll use a single socket
		DnetConnection c = new DnetConnection( inbandSocket );
		connections[address.toString()] = c;
	}

	final public DnetConnection[char[]] getAll() {
		return connections;
	}

	final public void broadcast( ubyte[] data, bool reliable ) {
		foreach ( ref DnetConnection c; connections ) {
			// data only goes to connected
			if ( c.state >= DnetConnection.STATE.CONNECTED ) {
				c.send( data, reliable );
			}
		}
	}

	/**
		Sends and receives data.
	*/
	final public void emit() {
		// remove disconnecting or timed-out connections
		cleanupConnections();

		// remove old challenges
		cleanupChallenges();

		// get and process out-of-band packets (e.g., connection requests)
		listenForOutOfBand();

		// get and process in-band packets
		listenForInBand();

		// issue onMessage() for each connection
		issueMessageEvents();

		// transmit for each connection
		foreach ( ref DnetConnection c; connections ) {
			c.transmit( false );
		}
	}

	/**
		Walks through connections and calls onMessage() for those having receiveQueue.length
		greater than 0.
	*/
	private void issueMessageEvents() {
		foreach ( ref DnetConnection c; connections ) {
			if ( !c.connected() ) {
				continue;
			}
			if ( c.receiveQueue.length > 0 ) {
				onMessage( c );
			}
		}
	}

	/**
		Called when unknown out-of-band packet is received for processing.
		args hold the arguments. Return true if packet has been successfully
		processed, return false otherwise.
		NOTE: if you store args for later use, please store the copy of it.
	*/
	public bool onOOBpacket( char[][] args ) {
		return false;
	}

	/**
		Called when connection request from addr is being processed. userData
		holds the user data specified in DnetConnection.connectTo(). You may want
		refuse the connection by returning false. You may also fill the reason with refusal
		_reason text, which will be sent to addr and trigger DnetConnection.onMessage() there.
		NOTE: if you store the userData for later use, please store the copy of it.
	*/
	public bool onConnect( DnetAddress addr, char[] userData, out char[] reason ) {
		return true;
	}

	/**
		Called when c is being disconnected.
	*/
	public void onDisconnect( ref DnetConnection c ) {

	}

	/**
		Called when message has been received from c.
		Place your processing here.
	*/
	public void onMessage( ref DnetConnection c ) {

	}

	version ( Tango ) {
		private void sendOOB( DnetAddress to, char[] fmt, ... ) {
			.sendOOB( loginSocket, to, fmt, _arguments, _argptr );
		}
	}
	else {
		private void sendOOB( DnetAddress to, ... ) {
			.sendOOB( loginSocket, to, _arguments, _argptr );
		}
	}

	private void cleanupConnections() {
		long	dropPoint = getUTCtime() - 8000;

		for ( size_t i = 0; i < connections.values.length; i++ ) {
			DnetConnection	c = connections.values[i];

			// delete disconnected connections
			if ( c.state == DnetConnection.STATE.DISCONNECTED ) {
				version ( Tango ) {
					Stdout.format( "{}: deleting disconnected connection\n", c.remoteAddress ).newline;
				}
				else {
					writefln( "%s: deleting disconnected connection", c.remoteAddress );
				}
				onDisconnect( c );
				connections.remove( c.remoteAddress.toString() );
				continue;
			}
			if ( c.state < DnetConnection.STATE.CONNECTED ) {
				continue;		// not connected
			}
			if ( c.lastReceive < dropPoint ) {
				version ( Tango ) {
					Stdout( "deleting timed-out connection\n" ).newline;
				}
				else {
					writefln( "deleting timed-out connection" );
				}
				onDisconnect( c );
				connections.remove( c.remoteAddress.toString() );
			}
		}
	}

	private void cleanupChallenges() {
		long	dropPoint = getUTCtime() - 3000;

		for ( size_t i = 0; i < challenges.values.length; i++ ) {
			if ( challenges.values[i].time < dropPoint ) {
				challenges.remove( challenges.values[i].address.toString() );
			}
		}
	}

	private void listenForOutOfBand() {
		PacketBuf	packetBuffer;
		auto 		buff = DnetBuffer( packetBuffer );
		DnetAddress	addr;

		int	size = loginSocket.receiveFrom( buff, addr );
		while ( size > 0 ) {
			// check for undersize packet
			if ( size < 4 ) {
				version ( Tango ) {
					Stdout.format( "{}: undersize packet", addr ).newline;
				}
				else {
					writefln( "%s: undersize packet", addr );
				}
				size = loginSocket.receiveFrom( buff, addr );
				continue;
			}

			if ( *cast( int * )buff.getBuffer != -1 ) {
				version ( Tango ) {
					Stdout.format( "{}: non-OOB packet received to login socket", addr ).newline;
				}
				else {
					writefln( "%s: non-OOB packet received to login socket", addr );
				}
				size = loginSocket.receiveFrom( buff, addr );
				continue;
			}

			char[]			cmd = cast( char[] )buff.getBuffer[int.sizeof..$];
			version ( Tango ) {
				// nothing
			}
			else {
				try {
					std.utf.validate( cmd );
				}
				catch ( UtfException e ) {
					writefln( "received invalid command: %s", e );
					break;
				}
			}
			scope char[][]	args = cmd.splitIntoTokens();

			switch ( args[0] ) {
				case "challenge_request":
					// do we have a challenge for this address?
					if ( ( addr.toString() in challenges ) is null ) {
						// we do not
						challenges[addr.toString()] = new Challenge( addr );
					}

					// send it back
					version ( Tango ) {
						sendOOB( addr, "challenge_response {0}", challenges[addr.toString()].toUtf8 );
					}
					else {
						sendOOB( addr, "challenge_response %s", challenges[addr.toString()] );
					}
					break;

				case "connection_request":
					if ( args.length != 4 ) {
						version ( Tango ) {
							Stdout.format( "{}: reject: malformed connection request", addr ).newline;
						}
						else {
							writefln( "%s: reject: malformed connection request", addr );
						}
						sendOOB( addr, "message \"malformed connection request\"" );
						break;
					}

					int		protoVer;
					uint	challengeNumber;

					version ( Tango ) {
						try {
							protoVer = toInt!( char )( args[1] );
							challengeNumber = toInt!( char )( args[2] );
						}
						catch ( IllegalArgumentException e ) {
							Stdout.format( "{0}: reject: {1}", addr, e ).newline;
							sendOOB( addr, "message \"{}\"", e );
							break;
						}
					}
					else {
						try {
							protoVer = toInt( args[1] );
							challengeNumber = toUint( args[2] );
						}
						catch ( ConvError e ) {
							writefln( "%s: reject: %s", addr, e );
							sendOOB( addr, "message \"%s\"", e );
							break;
						}
					}

					if ( protoVer != PROTOCOL_VERSION ) {
						version ( Tango ) {
							Stdout.format( "{}: reject: wrong protocol version", addr ).newline;
						}
						else {
							writefln( "%s: reject: wrong protocol version", addr );
						}
						sendOOB( addr, "message \"wrong protocol version\"" );
						break;
					}

					// do we have a challenge for this address?
					if ( ( addr.toString() in challenges ) !is null ) {
						// is the challenge valid?
						if ( challengeNumber != challenges[addr.toString()].number ) {
							version ( Tango ) {
								Stdout.format( "{}: reject: invalid challenge", addr ).newline;
							}
							else {
								writefln( "%s: reject: invalid challenge", addr );
							}
							sendOOB( addr, "message \"invalid challenge\"" );
							break;
						}
					}
					else {
						version ( Tango ) {
							Stdout.format( "{}: reject: no challenge", addr ).newline;
						}
						else {
							writefln( "%s: reject: no challenge", addr );
						}
						sendOOB( addr, "message \"no challenge\"" );
						break;
					}

					char[]	reason;

					// acknowledge the user of a new connection
					if ( !onConnect( addr, args[3], reason ) ) {
						version ( Tango ) {
							Stdout.format( "{0}: rejected by user: {1}", addr, reason ).newline;
							sendOOB( addr, "message \"{}\"", reason );
						}
						else {
							writefln( "%s: rejected by user: %s", addr, reason );
							sendOOB( addr, "message \"%s\"", reason );
						}
						break;
					}

					// add the address to the list of connections if it isn't yet added
					if ( ( addr.toString() in connections ) is null ) {
						add( addr );
						version ( Tango ) {
							Stdout.format( "{}: connect", addr ).newline;
						}
						else {
							writefln( "%s: connect", addr );
						}
					}
					else {
						// otherwise reuse already existing connection
						version ( Tango ) {
							Stdout.format( "{}: reconnect", addr ).newline;
						}
						else {
							writefln( "%s: reconnect", addr );
						}
					}

					connections[addr.toString()].setup( addr, null );	// FIXME: wrong public address

					// send connection acknowledgement to the remote host
					auto DnetAddress	inbandAddress = connections[addr.toString()].socket.getLocalAddress();
					version ( Tango ) {
						sendOOB( addr, "connection_response {0} {1} {2} {3}", inbandAddress.toAddrString, inbandAddress.port, addr.toAddrString, addr.port );
					}
					else {
						sendOOB( addr, "connection_response %s %d %s %d", inbandAddress.toAddrString, inbandAddress.port, addr.toAddrString, addr.port );
					}
					break;

				default:
					if ( !onOOBpacket( args ) ) {
						version ( Tango ) {
							Stdout.format( "unrecognised OOB packet {}", cmd ).newline;
						}
						else {
							writefln( "unrecognised OOB packet %s", cmd );
						}
					}
					break;
			}

			size = loginSocket.receiveFrom( buff, addr );
		}
	}

	private void listenForInBand() {
		PacketBuf	packetBuffer;
		auto		buff = DnetBuffer( packetBuffer );
		DnetAddress	addr;

		int size = inbandSocket.receiveFrom( buff, addr );
		while ( size > 0 ) {
			if ( ( addr.toString() in connections ) is null ) {
				// ignore in-band messages from unknown hosts
				version ( Tango ) {
					Stdout.format( "received unwanted packet from {}", addr ).newline;
				}
				else {
					writefln( "received unwanted packet from %s", addr );
				}
				size = inbandSocket.receiveFrom( buff, addr );
				continue;
			}

			// let the connection handle it
			connections[addr.toString()].processInBand( buff, addr );
			size = inbandSocket.receiveFrom( buff, addr );
		}
	}
}
