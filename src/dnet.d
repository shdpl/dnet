/**

*/
module dnet;

private import std.thread;
private import std.socket;
private import std.stdio;

/// Internet address. Same as std.socket.InternetAddress.
public typedef std.socket.InternetAddress InternetAddress;

/**
 Built in handler.
 Executed on each connect event with address of remote end as single argument.
 Returns:
  Should connection be accepted (use it to reject connections from clients if you are server).
*/
public bool dnet_on_connect(InternetAddress address){
	return true;
}

/**
 Built in handler.
 Executed on each disconnect event with address of remote end.
*/
public void dnet_on_disconnect(InternetAddress address){
}

/**
 Built in handler.
 Executed on each data receiving, with address of sender and data itself.
*/
public void dnet_on_receive(ubyte[] data, InternetAddress address){
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
	return true;
}

/**
 Shuts down all connections and clears resources.
 Use to shutdown server or client.
 After this call you will need to do dnet_init() again to use it.
*/
public void dnet_shutdown(){
}

/**
 Creates server that listens on address and port. Leave empty string for localhost.
 Returns:
  Success of creating. If true, server is up and listening. If false, error occured. Maybe port is in use?
*/
public bool dnet_server_create(char[] address, ushort port){
	return true;
}

/**
 Returns:
  Array of all connected clients.
*/
public InternetAddress[] dnet_server_get_clients(){
	return null;
}

/**
 Sends data to connected client.
*/
public void dnet_server_send(ubyte[] data, InternetAddress client){
}

/**
 Disconnects client.
*/
public void dnet_server_disconnect(InternetAddress client){
}

/**
 Connect to server listening on address and port. 
 Returns:
  Success of creating resourcess to server. If false then no resourcess could be established. $(RED True does not mean connection is accepted!) For that you will have to look for $(I on connect) event.
*/
public bool dnet_client_connect(InternetAddress address, ushort port){
	return true;
}

/**
 Sends data to connected server.
*/
public void dnet_client_send(ubyte[] data){
}

