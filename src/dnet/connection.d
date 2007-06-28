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
	size_t	PACKET_SIZE			= 1400;		/// Max. size of a single packet, in bytes
	size_t	MESSAGE_SIZE		= 16384;	/// Max. size of a message, in bytes
}

private const {
	int		FRAGMENT_SIZE		= PACKET_SIZE - 100;
	int		PROTOCOL_VERSION	= 1;
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
32	reliable acknowledge
[8	packet flags]

CMD_BYTES.RELIABLE
ubyte count
count times {
	ushort	length
	char[]	data
}
CMD_BYTES.UNRELIABLE
char[] data
-----------------------
only reliable data is fragmented

For the remote side, reliable and unreliable data are undistinguashable.
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
		const int RELIABLE_BACKUP_MASK	= RELIABLE_BACKUP - 1;

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
			Disconnecting	= ( 0 << 1 ),	// remote side is disconnecting
		}

		// protocol command bytes
		enum CMD_BYTES {
			RELIABLE,
			UNRELIABLE,
		}

		// data flow info
		struct FlowInfo {
			const int INFO_SIZE		= 32;	// number of packets info is kept for
			const int INFO_SIZE_MASK	= INFO_SIZE - 1;

			struct Times {
				long	sent;		// time when the packet has been sent
				long	received;	// time when the packet has been received
			}

			Times[INFO_SIZE]	times;
			int[INFO_SIZE]		latencies;
			int					latency;

			int					bandwidth;	// in bytes per second
			long				packetTime;	// time at which next packet should be sent

			void reset() {
				// reset everything but the bandwidth
				times[] = times.init;
				latencies[] = latencies.init;
				latency = latency.init;
				packetTime = packetTime.init;
			}

			void dataSent( int sequence, int packetSize ) {
				const int HEADER_OVERHEAD	= 48;
				times[sequence & INFO_SIZE_MASK].sent = getUTCtime();

				int msec = ( packetSize + HEADER_OVERHEAD ) * ( 10000 / bandwidth );
				packetTime = getUTCtime() + msec;
			}

			void dataReceived( int sequence ) {
				times[sequence & INFO_SIZE_MASK].received = getUTCtime();
				with ( times[sequence & INFO_SIZE_MASK] ) {
					latencies[sequence & INFO_SIZE_MASK] = received - sent;
				}
			}

			void calculateLatency( int sequence ) {
				int	total;
				int	count;

				for ( size_t i = 0; i < INFO_SIZE; i++ ) {
					if ( latencies[i] > 0 ) {
						total += latencies[i];
						count++;
					}
				}
				if ( !count ) {
					latency = 0;
				}
				else {
					latency = total / count;
				}
			}

			// returns true if bandwidth won't be chocked if we send another packet
			bool readyToTransmit() {
				if ( getUTCtime() < packetTime ) {
					return false;
				}
				return true;
			}
		}

		DnetSocket	socket;					// socket used for communications

		// connection information
		STATE		state;					// state of the connection
		uint		challengeNumber;
		DnetAddress	remoteAddress;
		DnetAddress	publicAddress;			// local address as translated by a NAT
		char[]		userData;
		long		lastReceive;			// time the last packet has been received
		long		lastTransmit;			// time the last packet has been sent

		// message fragmenting

		// flow control information
		FlowInfo	flowInfo;

		// data buffers
		DnetFifo	sendQueue;
		char		reliableSendQue[RELIABLE_BACKUP][];
		DnetFifo	receiveQueue;

		int			outgoingSequence = 1;	// outgoing packet sequence number
		int			incomingSequence;		// incoming packet sequence number
		int			outgoingAcknowledge;	// last outgoingSequence the remote side has
											// received
											// this comes in handy when it gets to calculating
											// pings and delta-compressing the messages
		int			reliableSequence;		// last added reliable message, not necesarily sent or acknowledged yet
		int			reliableAcknowledge;	// last acknowledged reliable message
		int			lastReliableSequence;	// last received reliable sequence
											// this is reliableAcknowledge on the remote side
											// it is also needed to detect reliable data loss
											// and to filter duplicated reliable data, which
											// can occur in case of a lossy connection
	}

	/**
	 * Constructor.
	 * Parameters:
	 * socket specifies _socket to use for communications.
	 * bandwidth specifies amount of downstream _bandwidth available, in bps.
	 * bandwidth defaults to 28.8Kbps.
	 */
	this( DnetSocket socket = null, int bandwidth = 28000 ) {
		if ( socket !is null ) {
			this.socket = socket;
		}
		else {
			this.socket = new DnetSocket();
		}

		sendQueue = new DnetFifo();
		receiveQueue = new DnetFifo();

		flowInfo.bandwidth = bandwidth;
	}

	private void setup( DnetAddress theRemoteAddress, DnetAddress thePublicAddress ) {
		remoteAddress = theRemoteAddress;
		publicAddress = thePublicAddress;

		outgoingSequence 	= outgoingSequence.init;
		incomingSequence 	= incomingSequence.init;
		outgoingAcknowledge	= outgoingAcknowledge.init;
		reliableSequence 	= reliableSequence.init;
		lastReliableSequence = lastReliableSequence.init;
		reliableAcknowledge = reliableAcknowledge.init;

		flowInfo.reset();

		state = STATE.CONNECTED;

		lastReceive = getUTCtime();
	}

	/**
	 * Disconnect from the server currently connected to.
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
	 * Connect to server (listening collection). If already connected, will disconnect
	 * and then connect again.
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

		state = STATE.CHALLENGING;		// disconnected -> challenging
		lastTransmit = -9999;			// challenge request will be sent immediately
	}

	/**
	 * Returns true if _connected, elsewise returns false.
	 */
	final public bool connected() {
		if ( state >= STATE.CONNECTED ) {
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
	 * null is returned if disconnected.
	 */
	final public DnetAddress getRemoteAddress(){
		if ( state == STATE.DISCONNECTED ) {
			return null;
		}
		return remoteAddress;
	}

	/**
	 * Returns latency value.
	 */
	final public int getLatency() {
		return flowInfo.latency;
	}

	/**
	 * Sets/gets available _bandwidth, in bps.
	 */
	public void bandwidth( int newBandwidth ) {
		flowInfo.bandwidth = newBandwidth;
	}

	/**
	 * ditto
	 */
	public int bandwidth() {
		return flowInfo.bandwidth;
	}

	/**
	 * Returns true if the bandwidth won't be chocked by sending another message.
	 * Elsewise false is returned.
	 */
	public bool readyToTransmit() {
		return flowInfo.readyToTransmit();
	}

	/**
	 * Buffers the data for sending. Set reliable to true if you want the buff
	 * retransmitted in case of packet loss.
	 * Throws: AssertException if not connected().
	 */
	final public void send( char[] buff, bool reliable )
	in {
		// don't even try to send until you get connected
		assert( state >= STATE.CONNECTED );
		assert( buff.length < MESSAGE_SIZE );
	}
	body {
		if ( reliable ) {
			// if we would be losing a reliable data that hasn't been acknowledged,
			// we must drop the connection
			if ( reliableSequence - reliableAcknowledge > RELIABLE_BACKUP ) {
				writefln( "irrecoverable loss of reliable data, disconnecting" );
				disconnect();
				return;
			}

			reliableSequence++;
			size_t	index = reliableSequence & RELIABLE_BACKUP_MASK;
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
		if ( state == STATE.DISCONNECTED ) {
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
		if ( state >= STATE.CONNECTED ) {
			long	dropPoint = getUTCtime() - 8000;
			if ( lastReceive < dropPoint ) {
				writefln( "connection timed-out" );
				state = STATE.DISCONNECTED;
			}
		}

		transmit( false );

		flowInfo.calculateLatency( outgoingSequence );
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

		//
		// write down packet data
		//

		char[PACKET_SIZE]	dataBuffer;
		DnetBuffer			data = new DnetBuffer( dataBuffer );

		preparePacket( data );

		//
		// write the packet
		//

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

		char[PACKET_SIZE]	packet;
		DnetBuffer			buff = new DnetBuffer( packet );

		// write packet header
		if ( packetFlags ) {
			buff.putInt( outgoingSequence | ( 1 << 31 ) );

			// write packet flags
			buff.putUbyte( packetFlags );
		}
		else {
			buff.putInt( outgoingSequence );
		}

		buff.putInt( outgoingAcknowledge );
		buff.putInt( lastReliableSequence );

		// write packet data
		buff.putData( data.getBuffer() );

		// send the packet
		socket.sendTo( buff.getBuffer(), remoteAddress );
//		writefln( "--> %s %d %d", remoteAddress, reliableSequence, reliableAcknowledge );

		// increment outgoing sequence
		outgoingSequence++;

		// mark time we last sent a packet
		lastTransmit = getUTCtime();

		// update data flow info
		flowInfo.dataSent( outgoingSequence, data.length );
	}

	private void transmitConnectionRequest() {
		if ( state == STATE.CHALLENGING || state == STATE.CONNECTING ) {
			// send connection requests once in five seconds
			if ( getUTCtime() - lastTransmit < 5000 ) {
				return;	// time hasn't come yet
			}

			char[PACKET_SIZE] packet;
			char[] request;

			switch ( state ) {
				case STATE.CHALLENGING:
					sendOOB( "challenge_request", remoteAddress );
					break;
				case STATE.CONNECTING:
					request = sformat( packet, "connection_request %d %d \"%s\"",
										PROTOCOL_VERSION, challengeNumber, userData );
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
		if ( state < STATE.CONNECTED ) {
			writefln( "unwanted packet from %s", addr );
			return;
		}

		// check if the packet is not from the server
		if ( addr != remoteAddress ) {
			writefln( "packet not from server: %s (should be %s)", addr, remoteAddress );
			return;
		}

		// mark time we last received a packet
		lastReceive = getUTCtime();

		// read packet header
		int		sequence = buff.readInt();

		uint	packetFlags;

		if ( sequence & ( 1 << 31 ) ) {
			sequence &= ~( 1 << 31 );

			// read packet flags
			packetFlags = buff.readUbyte();
		}

//		writefln( "drop %d", sequence - ( IncomingSequence + 1 ) );

		// check sequences
		if ( sequence <= incomingSequence ) {
			return;	// packet is stale
		}

		// check packet flags
		checkPacketFlags( packetFlags );

		outgoingAcknowledge = buff.readInt();
		reliableAcknowledge = buff.readInt();

		incomingSequence = sequence;

		// assemble fragments

		// parse the packet
		parsePacket( buff );

//		writefln( "<-- %s %d %d", remoteAddress, reliableSequence, reliableAcknowledge );

		// update data flow info
		flowInfo.dataReceived( outgoingAcknowledge );
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
				if ( state != STATE.CHALLENGING ) {
					if ( state == STATE.CONNECTING ) {
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

				state = STATE.CONNECTING;	// challenging -> connecting
				lastTransmit = -9999;		// connection request will fire immediately
				break;
			case "connection_response":
				if ( state != STATE.CONNECTING ) {
					if ( state == STATE.CONNECTED ) {
						writefln( "duplicate connection response received" );
					}
					else {
						writefln( "unwanted connection response received" );
					}
					break;
				}
				if ( args.length != 5 ) {
					writefln( "malformed connection response" );
					break;
				}
				ushort	remotePort, publicPort;
				try {
					remotePort = toUshort( args[2] );
					publicPort = toUshort( args[4] );
					
				}
				catch ( ConvError e ) {
					writefln( "bad connection respose: %s", e );
					break;
				}

				setup( new DnetAddress( args[1], remotePort ), new DnetAddress( args[3], publicPort ) );	// connecting -> connected
				break;
			default:
				if ( !onOOBpacket( args ) ) {
					writefln( "unrecognised OOB packet: %s", cmd );
				}
				break;
		}
	}

	private void preparePacket( ref DnetBuffer buff ) {
		// write reliable data
		buff.putUbyte( CMD_BYTES.RELIABLE );
		buff.putUbyte( reliableSequence - reliableAcknowledge );
		for ( size_t i = reliableAcknowledge + 1; i <= reliableSequence; i++ ) {
			size_t	index = i & RELIABLE_BACKUP_MASK;
			buff.putInt( i );
			buff.putString( reliableSendQue[index] );
		}

		// append unreliable data if there's space left
		buff.putUbyte( CMD_BYTES.UNRELIABLE );
		char[] tmp = sendQueue.get();
		while ( tmp.length > 0 ) {
			if ( buff.length + tmp.length > buff.size ) {
				break;	// overflowed
			}

			buff.putData( tmp );
			tmp = sendQueue.get();
		}
	}

	private void parsePacket( ref DnetBuffer buff ) {
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
					char[]	s = buff.readString();

					if ( sequence < lastReliableSequence ) {
						continue;		// we have already received it
					}

					if ( sequence > lastReliableSequence + 1 ) {
						// we have lost some of the data, so drop the connection
						writefln( "lost some reliable data" );
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

Collection is scalable enough to service up to 500 connections. It uses asynchronous
IO running in a single thread. The rationale behind this solution is that much more
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

	final public void broadcast( char[] data, bool reliable ) {
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
		foreach ( inout DnetConnection c; connections ) {
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
	 * Called when unknown out-of-band packet is received for processing.
	 * args hold the arguments. Return true if packet has been successfully
	 * processed, return false otherwise.
	 * NOTE: if you store args for later use, please store the copy of it.
	 */
	public bool onOOBpacket( char[][] args ) {
		return false;
	}

	/**
	 * Called when connection request from addr is being processed. userData
	 * holds the user data specified in DnetConnection.connectToServer(). You may want
	 * refuse the connection by returning false. You may also fill the reason with refusal
	 * _reason text, which will be sent to addr and trigger DnetConnection.onMessage() there.
	 * NOTE: if you store the userData for later use, please store the copy of it.
	 */
	public bool onConnect( DnetAddress addr, char[] userData, out char[] reason ) {
		return true;
	}

	/**
	 * Called when c is being disconnected.
	 */
	public void onDisconnect( ref DnetConnection c ) {

	}

	/**
	 * Called when message has been received from c.
	 * Place your processing here.
	 */
	public void onMessage( ref DnetConnection c ) {

	}

	private void cleanupConnections() {
		long	dropPoint = getUTCtime() - 8000;

		for ( size_t i = 0; i < connections.values.length; i++ ) {
			DnetConnection	c = connections.values[i];

			// delete disconnected connections
			if ( c.state == DnetConnection.STATE.DISCONNECTED ) {
				writefln( "%s: deleting disconnected connection", c.remoteAddress );
				onDisconnect( c );
				connections.remove( c.remoteAddress.toString() );
				continue;
			}
			if ( c.state < DnetConnection.STATE.CONNECTED ) {
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

			char[PACKET_SIZE] packet;
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

					if ( protoVer != PROTOCOL_VERSION ) {
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
						writefln( "%s: reconnect", addr );
					}

					connections[addr.toString()].setup( addr, null );	// FIXME: wrong public address

					// send connection acknowledgement to the remote host
					auto DnetAddress	inbandAddress = connections[addr.toString()].socket.getLocalAddress();
					reply = sformat( packet, "connection_response %s %d %s %d", inbandAddress.toAddrString, inbandAddress.port, addr.toAddrString, addr.port );
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
