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
packet header structure
-----------------------
31	sequence
[1	reliable flag, set if a packet carries reliable payload
31	reliable sequence
1	fragment flag
[16	fragment start
16	fragment length]]

[reliable data]
[unreliable data, if there's space left]
-----------------------
only reliable data is fragmented
header is 12 bytes in the worst scenario, and only 4 in the best one
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

		State		state;
		DnetSocket	Socket;

		DnetAddress	RemoteAddress;
		DnetFifo	SendQueue;
		DnetFifo	SendOOBQueue;
		DnetFifo	ReliableSendQue;
		DnetFifo	ReceiveQueue;
		long		LastReceive;
		long		LastTransmit;

		long		LastConnectionRetransmit;

		size_t		OutgoingSequence = 1;
		size_t		IncomingSequence;
		size_t		ReliableOutgoingSequence;
		size_t		ReliableIncomingSequence;
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
	public void connectToServer(DnetAddress remote_address, DnetAddress local_address = null){
		// disconnect from a server currently connected to
		disconnect();

		// set local address
		if ( local_address !is null ) {
			Socket.bind( local_address );
		}

		// set remote address
		RemoteAddress = remote_address;

		state = State.Connecting;		// disconnected -> connecting

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

		while( true ) {
			int size = Socket.receiveFrom( buff, addr );
			if ( size < 1 ) {
				break;
			}

			if ( *cast( int * )buff.buffer == -1 ) {
				// check out-of-band packets first
				char[]	cmd = buff.buffer[int.sizeof..$];
				writefln( "got %s", cmd );
				switch ( cmd ) {
					case "connection_response":
						// connecting / challenging -> connected
						setup();
						break;
					default:
						writefln( "unknown OOB message: %s", cmd );
						break;
				}
			}
			else {
				process( buff, addr );
			}
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

	public void transmit() {
		if ( state == State.Connecting ) {
			// send connection requests once in five seconds
			if ( getUTCtime() - LastConnectionRetransmit < 5000 ) {
				return;	// time hasn't come yet
			}

			writefln( "sending connection request" );

			sendOOB( format( "connection_request %d", DnetProtocolVersion ) );
			LastConnectionRetransmit = getUTCtime();
		}

		// transmit out-of-band packets
		char[]	tmp = SendOOBQueue.get();
		while ( tmp.length > 0 ) {
			Socket.sendTo( new DnetBuffer( tmp ), RemoteAddress );
			tmp = SendOOBQueue.get();
		}

		// transmit in-band packets
		if ( state < State.Connected ) {
			return;		// not yet connected
		}

		char[DnetPacketSize]	packet;
		int						packetLen;

		// write reliable data

		// combine multiple small packets into a big one
		tmp = SendQueue.get();
		while ( tmp.length > 0 ) {
			if ( packetLen + tmp.length > packet.sizeof ) {
				break;	// overflowed
			}

			packet[packetLen..packetLen+tmp.length] = tmp[];
			packetLen += tmp.length;
			tmp = SendQueue.get();
		}

		Socket.sendTo( new DnetBuffer( packet[0..packetLen] ), RemoteAddress );
	}

	public void process( DnetBuffer buff, DnetAddress addr ) {
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

		// check for undersize packet
		if ( buff.buffer.length < 4 ) {
			writefln( "undersize packet from %s", addr );
			return;
		}

		// check sequences
		// assemble fragments

		// put into receive queue
		ReceiveQueue.put( buff.dup );

		// mark time we last received a packet
		LastReceive = getUTCtime();
	}

	/**
	Time in miliseconds since last receive event.
	*/
	public long lastReceive(){
		return LastReceive;
//		return ( (getUTCtime() - LastReceive) / TicksPerSecond ) * 1000;
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
		DnetSocket Socket;
		DnetConnection[char[]] Connections;
		DnetFifo ReceiveQueue;
	}

	/**
	
	*/
	this(){
		Socket = new DnetSocket();
		ReceiveQueue = new DnetFifo();		
	}

	/**
	Make this collection act as a incoming server.
	*/
	public void bind(DnetAddress address){
		Socket.bind(address);
	}

	public DnetAddress getLocalAddress(){
		return Socket.getLocalAddress();
	}

	public void add(DnetAddress address){
		// we could spawn a new socket here...
		// but for now, we'll use a single socket
		DnetConnection c = new DnetConnection( Socket );
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
		// remove timed-out connections
		long	dropPoint = getUTCtime() - 8000;

		foreach ( inout DnetConnection c; Connections ) {
			if ( c.state >= DnetConnection.State.Connected && c.lastReceive < dropPoint ) {
				writefln( "deleting timed-out connection" );
				c.state = DnetConnection.State.Disconnected;
			}
		}

		// this should handle only new requests that are redirected to new socket
		// all established connections are spawned on other socket
		DnetBuffer buff;
		DnetAddress addr;
		int size = Socket.receiveFrom(buff, addr);

		while(size > 0){
			if ( *cast( int * )buff.buffer == -1 ) {
				// check out-of-band packets first
				char[]			cmd = buff.buffer[int.sizeof..$];
				scope char[][]	args = cmd.split();
				assert( args.length >= 1 );

				switch ( args[0] ) {
					case "connection_request":
						// arg1 is the protocol version
						if ( args.length != 2 ) {
							writefln( "malformed connection request from %s", addr );
							break;
						}

						int	protoVer;

						try {
							protoVer = toInt( args[1] );
						}
						catch ( ConvError e ) {
							writefln( "%s: reject: protocol version isn't a number: %s", addr, e );
							break;
						}

						if ( protoVer != DnetProtocolVersion ) {
							writefln( "%s: reject: wrong protocol version", addr );
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
						Connections[addr.toString()].sendOOB( "connection_response" );

						break;
					default:
						writefln( "unknown OOB message %s", cmd );
						break;
				}
			}
			else {
				// process in-band messages
				if ( ( addr.toString() in Connections ) is null ) {
					// ignore in-band messages from unknown hosts
					writefln( "received unwanted packet from %s", addr );
					size = Socket.receiveFrom( buff, addr );
					continue;
				}

				// let the connection handle it
				Connections[addr.toString()].process( buff, addr );
			}

			size = Socket.receiveFrom(buff, addr);
		}

		// transmit for each connection
		foreach ( inout DnetConnection c; Connections ) {
			c.transmit();
		}
	}
}
