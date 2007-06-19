/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

module dnet.connection;

import std.conv;
import std.stdio;
import std.random;
import std.string;
import std.date;
import std.utf;

import dnet.socket;
import dnet.fifo;
import dnet.buffer;
import dnet.utils;

public const {
	size_t	DnetPacketSize		= 1400;		/// Size of a single packet, in bytes
	size_t	DnetMessageSize		= 16384;	/// Overall size of a message, in bytes
}

private const {
	int		DnetFragmentSize	= DnetPacketSize - 100;
	int		DnetProtocolVersion	= 1;
}

private void sendOOB( DnetSocket socket, char[] buff, DnetAddress to ) {
	// not the smartest way...
	int	x = -1;
	char[]	s = ( cast( char * )&x )[0..x.sizeof] ~ buff;

	socket.sendTo( s, to );
}


/*
packet header structure
-----------------------
31	sequence
1	packet flags flag
32	reliable sequence
32	reliable acknowledge
[8	packet flags
[16	fragment start
16	fragment length]]]

[reliable data]
[unreliable data, if there's space left]
-----------------------
only reliable data is fragmented
header is 17 bytes in the worst scenario, and 12 in the best one

For the remote side, reliable and unreliable data are undistinguashable.
Reliable data is queued, then passed to the remote side. It will be retransmitted until
remote side acknowledges of the delivery. DnetConnection will try to combine multiple
small chunks of reliable data into a bigger one. Unreliable data will be appended
to the packet if there's enough space left. Whether it has been appended or not, it
will be discarded.
*/

/**
Simple name for two-end points connection, where one is allways local address.
Remote address' port *might* not be the same after receiving response.
It is because other side might spawn new socket to communicate with calling side.

TODO: Make sending and listening run in background threads.
Add latency estimation.
*/
public class DnetConnection {

	private {
		const int ReliableBackup	= 64;	// Size of the reliable send queue.

		// connection state
		enum State {
			Disconnected,		// not at all connected
			Connecting,			// sending challenge request
			Challenging,		// received challenge request, sending connection request
			Connected,			// got connection response, data can now be sent reliably
			Disconnecting,		// sending packets with Flags.Disconnecting
		}

		// packet flags
		enum Flags {
			Fragmented		= ( 0 << 1 ),	// packet is fragmented
			Disconnecting	= ( 1 << 1 ),	// remote side is disconnecting
		}

		DnetSocket	socket;					// socket used for communications

		// connection information
		State		state;					// state of the connection
		uint		challengeNumber;
		DnetAddress	remoteAddress;
		char[]		userData;
		long		lastReceive;			// time the last packet has been received
		long		lastTransmit;			// time the last packet has been sent

		// message fragmenting

		// data buffers
		DnetFifo	sendQueue;
		char		reliableSendQue[ReliableBackup][];
		DnetFifo	receiveQueue;

		int			outgoingSequence = 1;	// outgoing packet sequence number
		int			incomingSequence;		// incoming packet sequence number
		int			reliableSequence;		// last added reliable message, not necesarily sent or acknowledged yet
		int			remoteReliableSequence;	// reliableSequence of the remote side
		int			reliableAcknowledge;	// last acknowledged reliable message
	}

	/**
	 * Constructor.
	 */
	this( DnetSocket socket = null ) {
		if ( socket !is null ) {
			this.socket = socket;
		}
		else {
			this.socket = new DnetSocket();
		}

		sendQueue = new DnetFifo();
		receiveQueue = new DnetFifo();
	}

	private void setup( DnetAddress theRemoteAddress ) {
		remoteAddress = theRemoteAddress;

		outgoingSequence 	= outgoingSequence.init;
		incomingSequence 	= incomingSequence.init;
		reliableSequence 	= reliableSequence.init;
		remoteReliableSequence = remoteReliableSequence.init;
		reliableAcknowledge = reliableAcknowledge.init;

		state = State.Connected;

		lastReceive = getUTCtime();
	}

	/**
	 * Disconnect from the server currently connected to.
	 */
	final public void disconnect() {
		if ( state < State.Connected ) {
			return;		// not connected
		}

		state = State.Disconnecting;	// connected -> disconnecting

		transmit();
		transmit();

		onDisconnect();

		state = State.Disconnected;		// disconnecting -> disconnected
	}

	/**
	 * Connect to server (listening collection).
	 * Throws an UtfException if theUserData is not a valid UTF8 string.
	 * theUserData may not be longer than 1024 characters.
	*/
	final public void connectToServer( DnetAddress theRemoteAddress, char[] theUserData = null, DnetAddress theLocalAddress = null )
	in {
		std.utf.validate( theUserData );
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

		state = State.Challenging;		// disconnected -> challenging
		lastTransmit = -9999;			// challenge request will be sent immediately
	}

	/**
	 * Returns true if connected, elsewise returns false.
	 */
	final public bool connected() {
		if ( state >= State.Connected ) {
			return true;
		}
		return false;
	}

	/**
	 * Returns the address the connection is set-up on.
	 */
	final public DnetAddress getLocalAddress(){
		return socket.getLocalAddress();
	}

	/**
	 * Returns the address the connection is connecting/connected to.
	 * null is returned if disonnected.
	 */
	final public DnetAddress getRemoteAddress(){
		if ( state == State.Disconnected ) {
			return null;
		}
		return remoteAddress;
	}

	/**
	 * Buffers the data.
	 */
	final public void send( char[] buff, bool reliable )
	in {
		// don't even try to send until you get connected
		// commented out because currently user cannot find out whether he is connected
		// or not
//		assert( state >= State.Connected );
		assert( buff.length < DnetMessageSize );
	}
	body {
		if ( reliable ) {
			reliableSequence++;

			// if we would be losing a reliable data that hasn't been acknowledged,
			// we must drop the connection
			if ( reliableSequence - reliableAcknowledge == ReliableBackup + 1 ) {
				writefln( "irrecoverable loss of reliable data, disconnecting" );
				disconnect();
				return;
			}

			size_t	index = reliableSequence & ( ReliableBackup - 1 );
			if ( reliableSendQue[index] !is null ) {
				delete reliableSendQue[index];
			}
			reliableSendQue[index] = buff.dup;
		}
		else {
			sendQueue.put( buff.dup );
		}
	}


	/**
	 * Sends an out-of-band packet.
	 */
	final public void sendOOB( char[] buff, DnetAddress to ) {
		.sendOOB( socket, buff, to );
	}

	/**
	Reads next received data.
	*/
	final public char[] receive() {
		return receiveQueue.get();
	}

	/**
	Sends and receives data to other end.
	*/
	final public void emit() {
		if ( state == State.Disconnected ) {
			return;
		}

		// receive
		DnetBuffer buff;
		scope DnetAddress addr;

		int size = socket.receiveFrom( buff, addr );
		while ( size > 0 ) {
			if ( size < 4 ) {
				// check for undersize packet
				writefln( "undersize packet from %s", addr );
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
		if ( state >= State.Connected ) {
			long	dropPoint = getUTCtime() - 8000;
			if ( lastReceive < dropPoint ) {
				writefln( "connection timed-out" );
				state = State.Disconnected;
			}
		}

		transmit();
	}

	/**
	Time in miliseconds since last receive event.
	*/
	final public long lastReceiveTime(){
		return lastReceive;
	}

	private void transmit() {
		transmitConnectionRequest();

		// transmit in-band packets
		if ( state < State.Connected ) {
			return;		// not yet connected
		}

		void putReliableData( ref DnetBuffer buff ) {
			for ( size_t i = reliableAcknowledge + 1; i <= reliableSequence; i++ ) {
				size_t	index = i & ( ReliableBackup - 1 );
				buff.putData( reliableSendQue[index] );
			}
		}

		void putUnreliableData( ref DnetBuffer buff ) {
			char[] tmp = sendQueue.get();
			while ( tmp.length > 0 ) {
				if ( buff.length + tmp.length > buff.size ) {
					break;	// overflowed
				}

				buff.putData( tmp );
				tmp = sendQueue.get();
			}
		}

		//
		// assemble packet data
		//

		char[DnetPacketSize]	dataBuffer;
		DnetBuffer				data = new DnetBuffer( dataBuffer );

		// write reliable data
		putReliableData( data );

		// append unreliable data if there's space left
		putUnreliableData( data );

		//
		// write the packet
		//

		uint setPacketFlags() {
			uint	flags;

			if ( state == State.Disconnecting ) {
				// that's it, we're disconnecting
				flags |= Flags.Disconnecting;
			}
			if ( data.length > DnetFragmentSize ) {
				// message is large so it can't be sent in one piece
				flags |= Flags.Fragmented;
			}

			return flags;
		}

		// set packet flags
		uint packetFlags = setPacketFlags();

		char[DnetPacketSize]	packet;
		DnetBuffer				buff = new DnetBuffer( packet );

		// write packet header
		if ( packetFlags ) {
			buff.putInt( outgoingSequence | ( 1 << 31 ) );

			// write packet flags
			buff.putUbyte( packetFlags );
		}
		else {
			buff.putInt( outgoingSequence );
		}

		buff.putInt( reliableSequence );
		buff.putInt( remoteReliableSequence );

		if ( packetFlags & Flags.Fragmented ) {
			// TODO: fragment
		}

		// write packet data
		buff.putData( data.getBuffer() );

		// send the packet
		socket.sendTo( buff.getBuffer(), remoteAddress );
//		writefln( "--> %s %d %d", remoteAddress, reliableSequence, reliableAcknowledge );

		// increment outgoing sequence
		outgoingSequence++;

		// mark time we last sent a packet
		lastTransmit = getUTCtime();
	}

	private void transmitConnectionRequest() {
		if ( state == State.Challenging || state == State.Connecting ) {
			// send connection requests once in five seconds
			if ( getUTCtime() - lastTransmit < 5000 ) {
				return;	// time hasn't come yet
			}

			char[DnetPacketSize] packet;
			char[] request;

			switch ( state ) {
				case State.Challenging:
					sendOOB( "challenge_request", remoteAddress );
					break;
				case State.Connecting:
					request = sformat( packet, "connection_request %d %d \"%s\"",
										DnetProtocolVersion, challengeNumber, userData );
					sendOOB( request, remoteAddress );
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
		if ( state < State.Connected ) {
			writefln( "unwanted packet from %s", addr );
			return;
		}

		// check if the packet is not from the server
		if ( addr != remoteAddress ) {
			writefln( "packet not from server: %s (should be %s)", addr, remoteAddress );
			return;
		}

		// read packet header
		int		sequence = buff.readInt();

		uint	packetFlags;

		if ( sequence & ( 1 << 31 ) ) {
			sequence &= ~( 1 << 31 );

			// read packet flags
			packetFlags = buff.readUbyte();
		}

		int		reliable = buff.readInt();
		int		acknowledge = buff.readInt();

//		writefln( "drop %d", sequence - ( IncomingSequence + 1 ) );

		// check sequences
		if ( sequence <= incomingSequence ) {
			return;	// packet is stale
		}

		// check packet flags
		checkPacketFlags( packetFlags );

		remoteReliableSequence = reliable;
		reliableAcknowledge = acknowledge;
		incomingSequence = sequence;

		// assemble fragments

		// put into receive queue
		receiveQueue.put( buff.getBuffer[buff.bytesRead..$].dup );

//		writefln( "<-- %s %d %d", remoteAddress, reliableSequence, reliableAcknowledge );

		// mark time we last received a packet
		lastReceive = getUTCtime();
	}

	private void processOutOfBand( DnetBuffer buff, DnetAddress addr ) {
		char[]			cmd = buff.getBuffer[int.sizeof..$];
		try {
			std.utf.validate( cmd );
		}
		catch ( UtfException e ) {
			writefln( "received invalid command: %s", e );
			return;
		}
		scope char[][]	args = cmd.splitIntoTokens();

		switch ( args[0] ) {
			case "message":
				if ( args.length != 2 ) {
					writefln( "malformed message received" );
					break;
				}
				writefln( "message: %s", args[1] );
				onMessage( args[1] );
				break;
			case "challenge_response":
				if ( state != State.Challenging ) {
					if ( state == State.Connecting ) {
						writefln( "duplicate challenge received" );
					}
					else {
						writefln( "unwanted challenge received" );
					}
					break;
				}

				if ( addr != remoteAddress ) {
					writefln( "challenge not from server: %s", addr );
					break;
				}

				if ( args.length != 2 ) {
					writefln( "malformed challenge received" );
					break;
				}

				challengeNumber = toUint( args[1] );

				state = State.Connecting;	// challenging -> connecting
				lastTransmit = -9999;		// connection request will fire immediately
				break;
			case "connection_response":
				if ( state != State.Connecting ) {
					if ( state == State.Connected ) {
						writefln( "duplicate connection response received" );
					}
					else {
						writefln( "unwanted connection response received" );
					}
					break;
				}
				if ( args.length != 3 ) {
					writefln( "malformed connection response" );
					break;
				}
				ushort	port;
				try {
					port = toUshort( args[2] );
				}
				catch ( ConvError e ) {
					writefln( "bad connection respose: %s", e );
					break;
				}

				setup( new DnetAddress( args[1], port ) );	// connecting -> connected
				break;
			default:
				if ( !onOOBpacket( args ) ) {
					writefln( "unrecognised OOB packet: %s", cmd );
				}
				break;
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

TODO:
When client connects new connection is spawned, 
thus client now gets answer not from port requested but from some new port.
Make use of multithreading and socket sets.
*/
public class DnetCollection {

	private {
		class Challenge {
			this( DnetAddress addr ) {
				address	= addr;
				number	= rand();
				time	= getUTCtime();
			}

			char[] toString() {
				return format( "%d", number );
			}

			uint			number;		// challenge number
			DnetAddress		address;	// address of the requesting side
			long			time;		// time when challenge was created
		}

		Challenge[char[]]		challenges;

		DnetSocket				loginSocket;	// used to listen for connection requests
		DnetSocket				inbandSocket;
		DnetConnection[char[]]	connections;
		DnetFifo				receiveQueue;
	}

	/**
	
	*/
	this(){
		loginSocket = new DnetSocket();
		inbandSocket = new DnetSocket();
		receiveQueue = new DnetFifo();		
	}

	/**
	Make this collection act as a incoming server.
	*/
	final public void bind( DnetAddress address, DnetAddress inbandAddress )
	in {
		assert( address !is null );
		assert( inbandAddress !is null );
	}
	body {
		loginSocket.bind(address);
		inbandSocket.bind( inbandAddress );
	}

	final public DnetAddress getLocalAddress(){
		return loginSocket.getLocalAddress();
	}

	private void add( DnetAddress address ) {
		// we could spawn a new socket here...
		// but for now, we'll use a single socket
		DnetConnection c = new DnetConnection( inbandSocket );
		c.setup( address );
		connections[address.toString()] = c;
	}

	final public DnetConnection[char[]] getAll() {
		return connections;
	}

	final public void broadcast( char[] data, bool reliable ) {
		foreach ( DnetConnection c; connections ) {
			// data only goes to connected
			if ( c.state >= DnetConnection.State.Connected ) {
				c.send( data, reliable );
			}
		}
	}

	/**
	Reads next received data.
	*/
	final public char[] receive() {
		return receiveQueue.get();
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

		// transmit for each connection
		foreach ( inout DnetConnection c; connections ) {
			c.transmit();
		}
	}

	/**
	*/
	public bool onConnect( DnetAddress addr, char[] userData, out char[] reason ) {
		return true;
	}

	/**
	*/
	public void onDisconnect( DnetConnection c ) {

	}

	/**
	*/
	public bool onOOBpacket( char[][] args ) {
		return false;
	}

	private void cleanupConnections() {
		long	dropPoint = getUTCtime() - 8000;

		for ( size_t i = 0; i < connections.values.length; i++ ) {
			DnetConnection	c = connections.values[i];

			// delete disconnected connections
			if ( c.state == DnetConnection.State.Disconnected ) {
				writefln( "%s: deleting disconnected connection", c.remoteAddress );
				onDisconnect( c );
				connections.remove( c.remoteAddress.toString() );
				continue;
			}
			if ( c.state < DnetConnection.State.Connected ) {
				continue;		// not connected
			}
			if ( c.lastReceive < dropPoint ) {
				writefln( "deleting timed-out connection" );
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
		DnetBuffer buff;
		DnetAddress addr;
		int size = loginSocket.receiveFrom( buff, addr );

		while ( size > 0 ) {
			// check for undersize packet
			if ( size < 4 ) {
				writefln( "%s: undersize packet", addr );
				size = loginSocket.receiveFrom( buff, addr );
				continue;
			}

			if ( *cast( int * )buff.getBuffer != -1 ) {
				writefln( "%s: non-OOB packet received to login socket", addr );
				size = loginSocket.receiveFrom( buff, addr );
				continue;
			}

			char[DnetPacketSize] packet;
			char[]			reply;
			char[]			cmd = buff.getBuffer[int.sizeof..$];
			try {
				std.utf.validate( cmd );
			}
			catch ( UtfException e ) {
				writefln( "received invalid command: %s", e );
				break;
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
					reply = sformat( packet, "challenge_response %s", challenges[addr.toString()] );
					sendOOB( loginSocket, reply, addr );
					break;

				case "connection_request":
					if ( args.length != 4 ) {
						writefln( "%s: reject: malformed connection request", addr );
						sendOOB( loginSocket, "message \"malformed connection request\"", addr );
						break;
					}

					int		protoVer;
					uint	challengeNumber;

					try {
						protoVer = toInt( args[1] );
						challengeNumber = toUint( args[2] );
					}
					catch ( ConvError e ) {
						writefln( "%s: reject: %s", addr, e );
						reply = sformat( packet, "message \"%s\"", e );
						sendOOB( loginSocket, reply, addr );
						break;
					}

					if ( protoVer != DnetProtocolVersion ) {
						writefln( "%s: reject: wrong protocol version", addr );
						sendOOB( loginSocket, "message \"wrong protocol version\"", addr );
						break;
					}

					// do we have a challenge for this address?
					if ( ( addr.toString() in challenges ) !is null ) {
						// is the challenge valid?
						if ( challengeNumber != challenges[addr.toString()].number ) {
							writefln( "%s: reject: invalid challenge" );
							sendOOB( loginSocket, "message \"invalid challenge\"", addr );
							break;
						}
					}
					else {
						writefln( "%s: reject: no challenge" );
						sendOOB( loginSocket, "message \"no challenge\"", addr );
						break;
					}

					char[]	reason;

					// acknowledge the user of a new connection
					if ( !onConnect( addr, args[3], reason ) ) {
						writefln( "%s: rejected by user: %s", addr, reason );
						reply = sformat( packet, "message \"%s\"", reason );
						sendOOB( loginSocket, reply, addr );
						break;
					}

					// add the address to the list of connections if it isn't yet added
					if ( ( addr.toString() in connections ) is null ) {
						add( addr );
						writefln( "%s: connect", addr );
					}
					else {
						// otherwise reuse already existing connection
						connections[addr.toString()].setup( addr );
						writefln( "%s: reconnect", addr );
					}

					// send connection acknowledgement to the remote host
					auto DnetAddress	inbandAddress = connections[addr.toString()].socket.getLocalAddress();
					reply = sformat( packet, "connection_response %s %d", inbandAddress.toAddrString, inbandAddress.port );
					sendOOB( loginSocket, reply, addr );
					break;

				default:
					if ( !onOOBpacket( args ) ) {
						writefln( "unrecognised OOB packet %s", cmd );
					}
					break;
			}

			size = loginSocket.receiveFrom(buff, addr);
		}
	}

	private void listenForInBand() {
		DnetBuffer buff;
		DnetAddress addr;

		int size = inbandSocket.receiveFrom( buff, addr );
		while ( size > 0 ) {
			if ( ( addr.toString() in connections ) is null ) {
				// ignore in-band messages from unknown hosts
				writefln( "received unwanted packet from %s", addr );
				size = inbandSocket.receiveFrom( buff, addr );
				continue;
			}

			// let the connection handle it
			connections[addr.toString()].processInBand( buff, addr );
			size = inbandSocket.receiveFrom( buff, addr );
		}
	}
}
