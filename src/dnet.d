/**
*/
module dnet;

private import std.thread;
public import std.socket; // we need InternetAddress defined
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
private Address Server;
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
	bool function(InternetAddress) func_connect=&dnet_on_connect,
	//bool(*func_connect)(InternetAddress)=&dnet_on_connect, 
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
	if (IsServer){
		foreach(InternetAddress a; Clients.values)
			dnet_server_disconnect(a);
	}
	else {
		ubyte[] buff = [PacketType.DISCONNECT];
		Socket.sendTo(buff, Server);
	}

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
	writefln("server create");
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
	return Clients.values;
}

/**
 Sends data to connected client.
*/
public void dnet_server_send(ubyte[] data, InternetAddress client){
	ubyte[] buff = [PacketType.RECEIVE];
	Socket.sendTo(buff ~ data, client);
}

/**
 Disconnects client.
*/
public void dnet_server_disconnect(InternetAddress client){
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
	writefln("client connect");
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
	ubyte[] buff = [PacketType.RECEIVE] ;
	Socket.sendTo(buff ~ data, Server);
}



private int dnet_listening_func(void* unused){
	writefln("listening thread initialized");

	Address address;
	int size;
	ubyte[1024] buff;
	ubyte[] data;

	while (IsAlive){
		size = Socket.receiveFrom(buff, address);
		if (size > 0){
			writefln("packet received");
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

	writefln("terminating listening thread");
	return 0;
}

