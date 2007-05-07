/**

*/
module dnet;

private import std.thread;
private import std.socket;
private import std.stdio;

/// Internet address. Same as std.socket.InternetAddress.
//public typedef std.socket.InternetAddress InternetAddress;


private enum PacketType : ubyte {
	NONE,
	CONNECT,
	DISCONNECT,
	RECEIVE
}

private UdpSocket Socket;
private bool IsAlive = false;
private bool IsServer = false;
private InternetAddress[] Clients;
private InternetAddress Server;
private bool(*OnConnect)(InternetAddress);
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
	writefln("Got connect event from " ~ address.toString());
	return true;
}

/**
 Built in handler.
 Executed on each disconnect event with address of remote end.
*/
public void dnet_on_disconnect(InternetAddress address){
	writefln("Got diconnect event from " ~ address.toString());
}

/**
 Built in handler.
 Executed on each data receiving, with address of sender and data itself.
*/
public void dnet_on_receive(ubyte[] data, InternetAddress address){
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
	bool(*func_connect)(InternetAddress)=&dnet_on_connect, 
	void(*func_disconnect)(InternetAddress)=&dnet_on_disconnect, 
	void(*func_receive)(ubyte[], InternetAddress)=&dnet_on_receive
	){

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
	IsAlive = false;
	Clients.length = 0;
	Socket = null;
}

/**
 Creates server that listens on address and port. Leave empty string for localhost.
 Returns:
  Success of creating. If true, server is up and listening. If false, error occured. Maybe port is in use?
*/
public bool dnet_server_create(char[] address, ushort port){
	writefln("server create");
	try {
		InternetAddress a = new InternetAddress(address, 3333);
		Socket.bind(a);
		IsServer = true;
		Clients.length = 0;

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
	return Clients;
}

/**
 Sends data to connected client.
*/
public void dnet_server_send(ubyte[] data, InternetAddress client){
	Socket.sendTo([cast(ubyte)PacketType.RECEIVE] ~ data, client);
}

/**
 Disconnects client.
*/
public void dnet_server_disconnect(InternetAddress client){
	InternetAddress[] tmp;
	foreach(InternetAddress a; Clients){
		if (client != a){
			tmp.length = tmp.length + 1;
			tmp[length - 1] = a;
		}
	}
}

/**
 Connect to server listening on address and port. 
 Returns:
  Success of creating resourcess to server. If false then no resourcess could be established. $(RED True does not mean connection is accepted!) For that you will have to look for $(I on connect) event.
*/
public bool dnet_client_connect(char[] address, ushort port){
	writefln("client connect");
	IsServer = false;
	IsAlive = true;
	Server = new InternetAddress(address, port);
	Listener = new Thread(&dnet_listening_func, null);
	Listener.start();
	return true;
}

/**
 Sends data to connected server.
*/
public void dnet_client_send(ubyte[] data){
	Socket.sendTo([cast(ubyte)PacketType.RECEIVE] ~ data, Server);
}



private int dnet_listening_func(void* unused){
	writefln("listening thread initialized");

	Address address;
	int size;
	ubyte[1024] buff;
	ubyte type; // packet type
	ubyte[] data; // packet data

	while (IsAlive){
		size = Socket.receiveFrom(buff, address);
		if (size > 1){
			writefln("packet received");
			type = buff[0];
			data = buff[1..size].dup;

			switch (type){
				case PacketType.CONNECT:
					if (IsServer){
						if (OnConnect(cast(InternetAddress)address)){
							writefln("added client on list");
							// todo
						}
						// else reject connection
					}
					else{
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

	writefln("terminating listening thread");
	return 0;
}

