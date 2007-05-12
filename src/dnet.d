/*

Copyright (c) 2007 Bane <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

/**

TODO:
- packet reliability
- ordered arrival
- timeout detection when no traffic (pinging thread?)

-replace all ubyte with char (char is unsigned byte, no need for ubyte)
-wrap all asserts in debug blocks. when compiled with -release asserts are not removed, but program exists withouth any message

*/
module dnet;

version(Windows) pragma(lib, "ws2_32.lib");

private import std.thread;
public import std.socket; // we need InternetAddress publicly defined
private import std.stdio;

private enum PacketType : ubyte {
	NONE,
	CONNECT,
	DISCONNECT,
	RECEIVE
}

private UdpSocket Socket;
private bool IsAlive = false;
private bool IsServer = false;
private InternetAddress[char[]] Clients;
private InternetAddress Server;
//private bool(*OnConnect)(InternetAddress);
private bool function(InternetAddress) OnConnect;
private void(*OnDisconnect)(InternetAddress);
private void(*OnReceive)(ubyte[], InternetAddress);
private Thread Listener;



/**
 Built in handler.
 Executed on each connect event with address of remote end as single argument.
 Returns:
  Should connection be accepted (use it to reject connections from clients if you are server).
*/
public bool dnet_on_connect(InternetAddress address){
	debug {
		writefln("dnet on connect");
		assert(Socket != null);
		assert(IsAlive);
	}
	writefln("Got connect event from " ~ address.toString());
	return true;
}

/**
 Built in handler.
 Executed on each disconnect event with address of remote end.
*/
public void dnet_on_disconnect(InternetAddress address){
	debug {
		writefln("dnet on disconnect");
		assert(Socket != null);
		assert(IsAlive);
	}
	writefln("Got diconnect event from " ~ address.toString());
}

/**
 Built in handler.
 Executed on each data receiving, with address of sender and data itself.
*/
public void dnet_on_receive(ubyte[] data, InternetAddress address){
	debug {
		writefln("dnet on receive");
		assert(Socket != null);
		assert(IsAlive);
	}
	writefln("Got receive event from " ~ address.toString() ~ " with data '" ~ cast(char[])data ~ "'");
}


/**
 Initialize dnet before use. 
 Must be done on both client and server before any other calls. 
 Arguments are pointers to function that will handle events.
 You can leave default values for built in handlers, set null to disable that event handling,  
 or you can use your custom event handlers.
 Returns:
  Initialization success. If false then you can't use lib.
*/
public bool dnet_init(
	bool function(InternetAddress) func_connect=&dnet_on_connect,
	//bool(*func_connect)(InternetAddress)=&dnet_on_connect, 
	void(*func_disconnect)(InternetAddress)=&dnet_on_disconnect, 
	void(*func_receive)(ubyte[], InternetAddress)=&dnet_on_receive
	){

	debug
		writefln("dnet init");

	OnConnect = func_connect;
	OnDisconnect = func_disconnect;
	OnReceive = func_receive;

	Socket = new UdpSocket(AddressFamily.INET);
	Socket.blocking(true);
	IsAlive = Socket.isAlive;
	return IsAlive;
}

/**
 Shuts down all connections and clears resources.
 Use to shutdown server or client.
 After this call you will need to do dnet_init() again to use it.
*/
public void dnet_shutdown(){
	debug {
		writefln("dnet shutdown");
		assert(Socket != null);
		assert(IsAlive);
	}

	if (IsServer){
		foreach(InternetAddress a; Clients.values)
			dnet_server_disconnect(a);
	}
	else {
		ubyte[] buff = [PacketType.DISCONNECT];
		Socket.sendTo(buff, Server);
	}

	Listener = null;
	IsAlive = false;
	foreach(char[] k, InternetAddress v; Clients)
		Clients.remove(k);
	Socket = null;
}

/**
 Creates server that listens on address and port. Leave empty string for localhost.
 Returns:
  Success of creating. If true, server is up and listening. If false, error occured. Maybe port is in use?
*/
public bool dnet_server_create(char[] address, ushort port){
	debug
		writefln("dnet server create");
	try {
		InternetAddress a = new InternetAddress(address, 3333);
		Socket.bind(a);
		IsServer = true;

		Listener = new Thread(&dnet_listening_func, null);
		Listener.start();
		return true;
	}
	catch {
		return false;
	}
}

/**
 Returns:
  Array of all connected clients.
*/
public InternetAddress[] dnet_server_get_clients(){
	debug {
		writefln("dnet server get clients");
		assert(Socket != null);
		assert(IsServer);
		assert(IsAlive);
	}

	return Clients.values;
}

/**
 Sends data to connected client.
*/
public void dnet_server_send(ubyte[] data, InternetAddress client){
	debug {
		writefln("dnet server send");
		assert(Socket != null);
		assert(IsServer);
		assert(IsAlive);
	}

	ubyte[] buff = [PacketType.RECEIVE];
	Socket.sendTo(buff ~ data, client);
}

/**
 Disconnects client.
*/
public void dnet_server_disconnect(InternetAddress client){
	debug {
		writefln("dnet server disconnect");
		assert(Socket != null);
		assert(IsServer);
		assert(IsAlive);
	}

	//Socket.sendTo(cast(void[])[PacketType.DISCONNECT], client);
	OnDisconnect(client);
	Clients.remove(client.toString());
}

/**
 Connect to server listening on address and port. 
 Returns:
  Success of creating resourcess to server. If false then no resourcess could be established. $(RED True does not mean connection is accepted!) For that you will have to look for $(I on connect) event.
*/
public bool dnet_client_connect(char[] address, ushort port){
	debug
		writefln("dnet client connect");
	IsServer = false;
	IsAlive = true;
	Server = new InternetAddress(address, port);
	Listener = new Thread(&dnet_listening_func, null);
	Listener.start();
	ubyte[] buff = [PacketType.CONNECT];
	Socket.sendTo(buff, Server);
	return true;
}

/**
 Sends data to connected server.
*/
public void dnet_client_send(ubyte[] data){
	debug {
		writefln("dnet client send");
		assert(Socket != null);
		assert(!IsServer);
		assert(IsAlive);
	}
	ubyte[] buff = [PacketType.RECEIVE] ;
	Socket.sendTo(buff ~ data, Server);
}



private int dnet_listening_func(void* unused){
	debug writefln("dnet listening thread initialized");
	assert(Socket != null);

	Address address;
	int size;
	ubyte[1024] buff;
	ubyte[] data;

	while (IsAlive){
		size = Socket.receiveFrom(buff, address);
		if (size > 0){
			debug writefln("dnet packet received");
			data = buff[1..size].dup;

			switch (buff[0]){
				case PacketType.CONNECT:
					if (IsServer){
						if (OnConnect == null || OnConnect(cast(InternetAddress)address)) {
							Clients[address.toString()] = cast(InternetAddress)address;
							ubyte[] buff2 = [PacketType.CONNECT] ;
							Socket.sendTo(buff2, cast(InternetAddress)address);
						}
					}
					else {
						if (OnConnect != null)
							OnConnect(cast(InternetAddress)address);
					}
					break;
				case PacketType.DISCONNECT:
					if (OnDisconnect != null)
						OnDisconnect(cast(InternetAddress)address);
					break;
				case PacketType.RECEIVE:
					if (OnReceive != null)
						OnReceive(data, cast(InternetAddress)address);
					break;
				default:
					break;
			}

		}
	}

	debug writefln("dnet terminating listening thread");
	return 0;
}

