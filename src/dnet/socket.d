/*

Copyright (c) 2007 Branimir Milosavljevic <branimir.milosavljevic@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

module dnet.socket;

version ( Tango ) {
	import tango.io.Stdout;
	import tango.net.Socket;
	import tango.net.InternetAddress;

	class UdpSocket: Socket {
		/// Constructs a blocking UDP Socket.
		this( AddressFamily family ) {
			super( family, SocketType.DGRAM, ProtocolType.UDP );
		}
	}
}
else {
	import std.stdio;
	import std.socket;
	import std.c.time;
}

version (Windows) {
	pragma(lib, "ws2_32.lib");
	pragma(lib, "wsock32.lib");
}

import dnet.buffer;


/**
 Abstraction of IP v4 address.
*/
public class DnetAddress {

	private {
		InternetAddress Address;
	}

	/**
	 Any local address.
	 */
	this(ushort port){
		Address = new InternetAddress( port );
	}

	/**
	 Create address from uint value and port number.
	*/
	this(uint ip, ushort port){
		Address = new InternetAddress( ip, port );
	}

	/**
	 Create address from human readable string and port number.
	*/
	this(char[] ip, ushort port){
		Address = new InternetAddress( ip, port );
	}

	/**
	 Returns address in human readable form (eg. address:port).
	*/
	char[] toAddrString() {
		return Address.toAddrString();
	}

	/**
	 Returns address port.
	*/
	ushort port() {
		return Address.port;
	}

	int opEquals( DnetAddress address ) {
		if ( address.Address.addr != Address.addr || address.Address.port != Address.port )
			return 0;
		else
			return 1;
	}

	version ( Tango ) {
		public char[] toUtf8(){
			return Address.toUtf8();
		}
		alias toUtf8 toString;
	}
	else {
		public char[] toString(){
			return Address.toString();
		}
	}
}



/**
 Abstract of UDP connectionless socket.
*/
public class DnetSocket {

	private {
		UdpSocket	Socket;
		long		bytesSent;
		long		bytesReceived;
	}

	/**
	*/
	this(){
		Socket = new UdpSocket(AddressFamily.INET);
		Socket.blocking(false);
	}

	/**
	 Resets sent/received bytes counters.
	*/
	public void resetCounters() {
		bytesSent = 0;
		bytesReceived = 0;
	}

	/**
	 Binds socket to an address.
	*/
	public void bind(DnetAddress address){
		Socket.bind(address.Address);
	}

	/**
	 Returns local end of socket connection.
	*/
	public DnetAddress getLocalAddress(){
		InternetAddress a = cast(InternetAddress)Socket.localAddress();
		return new DnetAddress( a.addr(), a.port() );
	}

	/**
	 Sends data to specified address.
	*/
	public void sendTo(void[] buff, DnetAddress address){
		//writefln("Socket %s sends to %s data: [%s]", 
		//	getLocalAddress.toString(), 
		//	address.toString(), 
		//	buff.buffer()
		//);
		Socket.sendTo(buff, address.Address);
		bytesSent += buff.length;
	}

	/**
	 Recieves data.
	 Incoming data is stored in buffer and address that is received from is written.
	*/
	public int receiveFrom( ref DnetBuffer buff, out DnetAddress address ) {
		buff.clear();

		ubyte[1400]	tmp;
		version ( Tango ) {
			Address	addr = Socket.newFamilyObject();
		}
		else {
			Address	addr;
		}
		int			size = Socket.receiveFrom( tmp, addr );

		if ( size > 0 ) {
			buff.putData( tmp[0..size] );
			bytesReceived += size;
		}
		version ( Tango ) {
			address = new DnetAddress( (cast(IPv4Address)addr).addr(), (cast(IPv4Address)addr).port() );
		}
		else {
			address = new DnetAddress( (cast(InternetAddress)addr).addr(), (cast(InternetAddress)addr).port() );
		}
		//if (size > 0){
	        //        writefln("Socket %s receives from %s data: [%s]",
        	//                getLocalAddress.toString(),
                //	        address.toString(),
                //        	buff.getBuffer()
	        //        );
		//}
		return size;
	}
}
