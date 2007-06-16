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

import dnet.socket;
import dnet.fifo;
import dnet.buffer;
import dnet.utils;

public const {
	size_t	DnetPacketSize		= 1400;		/// Size of a single packet, in bytes
	size_t	DnetMessageSize		= 16384;	/// Overall size of a message, in bytes
}

private const {
	int		DnetProtocolVersion	= 1;
}

/*
TODO: make use of multithreading and socket sets
*/

/*
packet header structure
-----------------------
31	sequence
[1	reliable flag, set if a packet carries reliable payload
32	reliable sequence
8	packet flags
[16	fragment start
16	fragment length]]

[reliable data]
[unreliable data, if there's space left]
-----------------------
only reliable data is fragmented
header is 20 bytes in the worst scenario, and only 4 in the best one
*/

/**
Simple name for two-end points connection, where one is allways local address.
Remote address' port *might* not be the same after receiving response.
It is because other side might spawn new socket to communicate with calling side.

For the remote side, reliable and unreliable data are undistinguashable.
Reliable data is queued, then passed to the remote side. It will be retransmitted until
remote side acknowledges of the delivery. DnetConnection will try to combine multiple
small chunks of reliable data into a bigger one. Unreliable data will be appended
to the packet if there's enough space left. Whether it has been appended or not, it
will be discarded.
*/
public class DnetConnection {
	private {
		// connection state
		enum State {
			Disconnected,
			Connecting,
			Challenging,
			Connected,
			Disconnecting,
			Zombie
		}

		// packet flags
		enum Flags {
			Fragmented		= ( 0 << 1 ),	// packet is fragmented
			Disconnecting	= ( 1 << 1 ),	// remote side is disconnecting
		}

		State		state;
		uint		challengeNumber;
		DnetSocket	Socket;

		DnetAddress	RemoteAddress;
		DnetFifo	SendQueue;
		DnetFifo	SendOOBQueue;
		DnetFifo	ReliableSendQue;
		DnetFifo	ReceiveQueue;
		long		LastReceive;
		long		LastTransmit;

		long		LastConnectionRetransmit;
		char[]		userData;

		uint		OutgoingSequence = 1;
		uint		IncomingSequence;
		uint		ReliableOutgoingSequence;
		uint		ReliableIncomingSequence;
	}

	this( DnetSocket socket = null ) {
		if ( socket !is null ) {
			Socket = socket;
		}
		else {
			Socket = new DnetSocket();
		}

		SendQueue = new DnetFifo();
		SendOOBQueue = new DnetFifo();
		ReliableSendQue = new DnetFifo();
		ReceiveQueue = new DnetFifo();
		LastReceive = getUTCtime();
	}

	private void setup() {
		OutgoingSequence = OutgoingSequence.init;
		IncomingSequence = IncomingSequence.init;
		ReliableOutgoingSequence = ReliableOutgoingSequence.init;
		ReliableIncomingSequence = ReliableIncomingSequence.init;

		state = State.Connected;

		LastReceive = getUTCtime();
	}

	/**
	Disconnect from the server currently connected to.
	*/
	public void disconnect() {
		if ( state < State.Connected ) {
			return;		// not connected
		}

		// TODO!!
		state = State.Disconnected;
	}

	/**
	Connect to server (listening collection).
	Will use handshaking to get remote_address from new spawned socket on server side.
	*/
	public void connectToServer( DnetAddress remote_address, char[] theUserData = null, DnetAddress local_address = null ) {
		// disconnect from the server currently connected to
		disconnect();

		// save off user-defined data
		userData = theUserData.dup;

		// set local address
		if ( local_address !is null ) {
			Socket.bind( local_address );
		}

		// set remote address
		RemoteAddress = remote_address;

		// disconnected -> challenging
		state = State.Challenging;

		// first connection request will be sent immediately
		LastConnectionRetransmit = -9999;
	}

	/**
	Point to point connecting.
	*/
	public void connectToPoint(DnetAddress remote_address){
		setup();

		RemoteAddress = remote_address;
	}

	public void connectToPoint(DnetAddress local_address, DnetAddress remote_address){
		Socket.bind(local_address);
		connectToPoint(remote_address);
	}


	public DnetAddress getLocalAddress(){
		return Socket.getLocalAddress();
	}
	public DnetAddress getRemoteAddress(){
		return RemoteAddress;
	}

	/**
	Buffers the data.
	*/
	public void send( char[] buff, bool reliable )
	in {
		// don't even try to send until you get connected
		// commented out because currently user cannot find out whether he is connected
		// or not
//		assert( state >= State.Connected );
	}
	body {
		reliable ? ReliableSendQue.put( buff.dup ) : SendQueue.put( buff.dup );
	}

	/**
	Buffers the data for sending as connectionless datagram.
	*/
	public void sendOOB( char[] buff ) {
		// not the smartest way...
		int	x = -1;
		char[]	s = ( cast( char * )&x )[0..x.sizeof] ~ buff;

		SendOOBQueue.put( s.dup );
	}

	/**
	Reads next received data.
	*/
	public DnetBuffer receive(){
		return new DnetBuffer(ReceiveQueue.get());
	}

	/**
	Sends and receives data to other end.
	*/
	public void emit(){
		// receive
		DnetBuffer buff;
		scope DnetAddress addr;

		int size = Socket.receiveFrom( buff, addr );
		while ( size > 0 ) {
			if ( size < 4 ) {
				// check for undersize packet
				writefln( "undersize packet from %s", addr );
				size = Socket.receiveFrom( buff, addr );
				continue;
			}

			if ( *cast( int * )buff.buffer == -1 ) {
				// check out-of-band packets first
				char[]			cmd = buff.buffer[int.sizeof..$];
				scope char[][]	args = cmd.split();	// BUGBUG: split doesn't consider quoted
													// text as a single word,
													// but we rely it does

				writefln( "got %s", cmd );
				switch ( args[0] ) {
					case "message":
						if ( args.length != 2 ) {
							writefln( "malformed message received" );
							break;
						}
						writefln( "message: %s", args[1] );
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

						if ( addr != RemoteAddress ) {
							writefln( "challenge not from server: %s", addr );
							break;
						}

						if ( args.length != 2 ) {
							writefln( "malformed challenge received" );
							break;
						}

						challengeNumber = toUint( args[1] );

						// challenging -> connecting
						state = State.Connecting;
						LastConnectionRetransmit = -9999;	// connection request will fire immediately
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
						// connecting -> connected
						setup();
						RemoteAddress = new DnetAddress( args[1], port );
						break;
					default:
						writefln( "unknown OOB message: %s", cmd );
						break;
				}
			}
			else {
				process( buff, addr );
			}

			// get next packet
			size = Socket.receiveFrom( buff, addr );
		}

		// check for time-out
		if ( state >= State.Connected ) {
			long	dropPoint = getUTCtime() - 8000;

			if ( LastReceive < dropPoint ) {
				writefln( "connection timed-out" );
				state = State.Disconnected;
			}
		}

		transmit();
	}

	/**
	Time in miliseconds since last receive event.
	*/
	public long lastReceive(){
		return LastReceive;
//		return ( (getUTCtime() - LastReceive) / TicksPerSecond ) * 1000;
	}

	private void transmit() {
		if ( state == State.Challenging || state == State.Connecting ) {
			// send connection requests once in five seconds
			if ( getUTCtime() - LastConnectionRetransmit < 5000 ) {
				return;	// time hasn't come yet
			}

			switch ( state ) {
				case State.Challenging:
					writefln( "sending challenge request" );
					sendOOB( "challenge_request" );
					break;
				case State.Connecting:
					writefln( "sending connection request" );
					sendOOB( format( "connection_request %d %d \"%s\"", DnetProtocolVersion, challengeNumber, userData ) );
					break;
			}

			LastConnectionRetransmit = getUTCtime();
		}

		// transmit out-of-band packets
		char[]	tmp = SendOOBQueue.get();
		while ( tmp.length > 0 ) {
			Socket.sendTo( tmp, RemoteAddress );
			tmp = SendOOBQueue.get();
		}

		// transmit in-band packets
		if ( state < State.Connected ) {
			return;		// not yet connected
		}

		char[DnetPacketSize]	packet;
		int						packetLen;

		// write sequence number

		// write reliable data

		// append unreliable data if there's space left
		tmp = SendQueue.get();
		while ( tmp.length > 0 ) {
			if ( packetLen + tmp.length > packet.sizeof ) {
				break;	// overflowed
			}

			packet[packetLen..packetLen+tmp.length] = tmp[];
			packetLen += tmp.length;
			tmp = SendQueue.get();
		}

		Socket.sendTo( packet[0..packetLen], RemoteAddress );

		// mark time we last sent
		LastTransmit = getUTCtime();
	}

	private void process( DnetBuffer buff, DnetAddress addr ) {
		// check in-bound packets
		// check unwanted packet
		if ( state < State.Connected ) {
			writefln( "unwanted packet from %s", addr );
			return;
		}

		// check if the packet is not from the server
		if ( addr != RemoteAddress ) {
			writefln( "packet not from server: %s (should be %s)", addr, RemoteAddress );
			return;
		}

		// check sequences

		// assemble fragments

		// put into receive queue
		ReceiveQueue.put( buff.dup );

		// mark time we last received a packet
		LastReceive = getUTCtime();
	}
}

/**
A collection of connections.
This can be a server if you bind socket and listen 
or it can be a client connected to multiple points.

TODO:
When client connects new connection is spawned, 
thus client now gets answer not from port requested but from some new port.
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

		DnetSocket				Socket;
		DnetSocket				InbandSocket;
		DnetConnection[char[]]	Connections;
		DnetFifo				ReceiveQueue;
	}

	/**
	
	*/
	this(){
		Socket = new DnetSocket();
		InbandSocket = new DnetSocket();
		ReceiveQueue = new DnetFifo();		
	}

	/**
	Make this collection act as a incoming server.
	*/
	public void bind(DnetAddress address, DnetAddress inbandAddress)
	in {
		assert( address !is null );
		assert( inbandAddress !is null );
	}
	body {
		Socket.bind(address);
		InbandSocket.bind( inbandAddress );
	}

	public DnetAddress getLocalAddress(){
		return Socket.getLocalAddress();
	}

	public void add(DnetAddress address){
		// we could spawn a new socket here...
		// but for now, we'll use a single socket
		DnetConnection c = new DnetConnection( InbandSocket );
		c.connectToPoint(address);
		Connections[address.toString()] = c;
	}

	public DnetConnection[char[]] getAll(){
		return Connections;
	}

	public void broadcast(char[] buff, bool reliable){
		foreach ( DnetConnection c; Connections ) {
			if ( c.state >= DnetConnection.State.Connected ) {
				c.send( buff, reliable );
			}
		}
	}

	/**
	Reads next received data.
	*/
	public DnetBuffer receive(){
		char[] tmp = ReceiveQueue.get();
		return new DnetBuffer(tmp);
	}

	/**
	Sends and receives data.
	*/
	public void emit(){
		void sendOOB( char[] buff, DnetAddress to ) {
			// not the smartest way...
			int	x = -1;
			char[]	s = ( cast( char * )&x )[0..x.sizeof] ~ buff;

			Socket.sendTo( s, to );
		}

		void checkForTimeouts() {
			long	dropPoint = getUTCtime() - 8000;

			for ( size_t i = 0; i < Connections.values.length; i++ ) {
				DnetConnection	c = Connections.values[i];

				if ( c.state < DnetConnection.State.Connected ) {
					continue;
				}
				if ( c.lastReceive < dropPoint ) {
					writefln( "deleting timed-out connection" );
					Connections.remove( c.getRemoteAddress.toString() );
				}
			}
		}

		void cleanupChallenges() {
			long	dropPoint = getUTCtime() - 3000;

			for ( size_t i = 0; i < challenges.values.length; i++ ) {
				if ( challenges.values[i].time < dropPoint ) {
					challenges.remove( challenges.values[i].address.toString() );
				}
			}
		}

		// remove timed-out connections
		checkForTimeouts();

		// remove old challenges
		cleanupChallenges();

		// this should handle only new requests that are redirected to new socket
		// all established connections are spawned on other socket
		DnetBuffer buff;
		DnetAddress addr;
		int size = Socket.receiveFrom(buff, addr);

		// process out-of-band packets (e.g., connection requests)
		while ( size > 0 ) {
			// check for undersize packet
			if ( size < 4 ) {
				writefln( "undersize packet from %s", addr );
				size = Socket.receiveFrom( buff, addr );
				continue;
			}

			if ( *cast( int * )buff.buffer == -1 ) {
				char[]			cmd = buff.buffer[int.sizeof..$];
				scope char[][]	args = cmd.split();	// BUGBUG: split doesn't consider quoted
													// text as a single word,
													// but we rely it does

				switch ( args[0] ) {
					case "challenge_request":
						// do we have a challenge for this address?
						if ( ( addr.toString() in challenges ) is null ) {
							// we do not
							challenges[addr.toString()] = new Challenge( addr );
						}

						// send it back
						sendOOB( format( "challenge_response %s", challenges[addr.toString()] ), addr );
						break;

					case "connection_request":
						if ( args.length < 3 ) {
							writefln( "%s: reject: malformed connection request", addr );
							sendOOB( "message \"malformed connection request\"", addr );
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
							sendOOB( format( "message \"%s\"", e ), addr );
							break;
						}

						if ( protoVer != DnetProtocolVersion ) {
							writefln( "%s: reject: wrong protocol version", addr );
							sendOOB( "message \"wrong protocol version\"", addr );
							break;
						}

						// do we have a challenge for this address?
						if ( ( addr.toString() in challenges ) !is null ) {
							// is the challenge valid?
							if ( challengeNumber != challenges[addr.toString()].number ) {
								writefln( "%s: reject: invalid challenge" );
								sendOOB( "message \"invalid challenge\"", addr );
								break;
							}
						}
						else {
							writefln( "%s: reject: no challenge" );
							sendOOB( "message \"no challenge\"", addr );
							break;
						}

						char[]	userData, reason;
						if ( args.length == 4 ) {
							userData = args[3];
						}

						// acknowledge the user of a new connection
						if ( !onConnect( addr, userData, reason ) ) {
							writefln( "%s: rejected by user: %s", addr, reason );
							sendOOB( format( "message \"%s\"", reason ), addr );
							break;
						}

						// add the address to the list of connections if it isn't yet added
						if ( ( addr.toString() in Connections ) is null ) {
							add( addr );
							writefln( "%s: connect", addr );
						}
						else {
							// otherwise reuse already existing connection
							Connections[addr.toString()].setup();
							writefln( "%s: reconnect", addr );
						}

						// setup the new connection
						Connections[addr.toString()].connectToPoint( addr );

						// send connection acknowledgement to the remote host
						auto DnetAddress	inbandAddress = Connections[addr.toString()].Socket.getLocalAddress();
						sendOOB( format( "connection_response %s %d", inbandAddress.toAddrString, inbandAddress.port ), addr );
						break;

					default:
						writefln( "unknown OOB message %s", cmd );
						break;
				}
			}

			size = Socket.receiveFrom(buff, addr);
		}

		// process in-band packets
		size = InbandSocket.receiveFrom( buff, addr );
		while ( size > 0 ) {
			if ( ( addr.toString() in Connections ) is null ) {
				// ignore in-band messages from unknown hosts
				writefln( "received unwanted packet from %s", addr );
				size = InbandSocket.receiveFrom( buff, addr );
				continue;
			}

			// let the connection handle it
			Connections[addr.toString()].process( buff, addr );
			size = InbandSocket.receiveFrom( buff, addr );
		}

		// transmit for each connection
		foreach ( inout DnetConnection c; Connections ) {
			c.transmit();
		}
	}

	public bool onConnect( DnetAddress addr, char[] userData, out char[] reason ) {
		return true;
	}
}
