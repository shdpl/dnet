/**
	Written by Dmitry Shalkhakov but placed into public domain.
*/

import dnet.utils;		// these are here only to keep the example library-independent
import dnet.socket;		// you shouldn't rely on their existence
import dnet.dnet;

class ClientHost {
	DnetHost		host;
	DnetConnection	conn;

	this( char[] localAddress = null, ushort localPort = 0 ) {
		host = new DnetHost( 33600, 33600, localAddress, localPort, false );
		host.connectionRequest = &handleConnectionRequest;
		host.connection = &handleConnection;
		host.disconnection = &handleDisconnection;
		host.messageSend = &handleMessageSend;
		host.messageReceive = &handleMessageReceive;
	}

	bool handleConnectionRequest( Address from, char[] userData, ref char[] reason ) {
		debugPrint( "client: connection" );
		return false;
	}

	void handleConnection( DnetConnection c ) {
		debugPrint( "client: connected to server" );
		conn = c;
	}

	void handleDisconnection( DnetConnection c, char[] reason ) {
		debugPrint( "client: disconnect" );
		conn = null;
	}

	void handleMessageSend( DnetConnection c ) {
		ubyte[15000] extraFoo;

		conn.send( cast( ubyte[] )"foo" );
		c.send( extraFoo );
	}

	void handleMessageReceive( DnetConnection c ) {
		ubyte[MESSAGE_LENGTH]	msg;

		while ( true ) {
			int l = c.receive( msg );
			if ( !l ) {
				break;
			}
			if ( cast( char[] )msg[0..l] == "bar" ) {
				debugPrint( "client: got bar" );
			}
			else if ( l == 15000 ) {
				debugPrint( "client: got extra bar" );
			}
		}
	}

	void emit() {
		host.emit();
	}
}

class ServerHost {
	DnetHost	host;

	this( char[] localAddress = null, ushort localPort = 0 ) {
		host = new DnetHost( 33600, 33600, localAddress, localPort );
		host.connectionRequest = &handleConnectionRequest;
		host.connection = &handleConnection;
		host.disconnection = &handleDisconnection;
		host.messageSend = &handleMessageSend;
		host.messageReceive = &handleMessageReceive;
	}

	bool handleConnectionRequest( Address from, char[] userData, ref char[] reason ) {
		debugPrint( "server: connection from " ~ typeToUtf8( from ) );
		return true;
	}

	void handleConnection( DnetConnection c ) {
		debugPrint( "server: client connected" );
	}

	void handleDisconnection( DnetConnection c, char[] reason ) {
		debugPrint( "server: client disconnected" );
	}

	void handleMessageSend( DnetConnection c ) {
		ubyte[15000]			extraBar;

		c.send( cast( ubyte[] )"bar" );
		c.send( extraBar );
	}
	
	void handleMessageReceive( DnetConnection c ) {
		ubyte[MESSAGE_LENGTH]	msg;

		while ( true ) {
			auto l = c.receive( msg );
			if ( !l ) {
				break;
			}
			if ( cast( char[] )msg[0..l] == "foo" ) {
				debugPrint( "server: got foo" );
			}
			else if ( l == 15000 ) {
				debugPrint( "server: got extra foo" );
			}
		}
	}

	void emit() {
		host.emit();
	}
}

int main( char[][] args ) {
	auto client = new ClientHost;
	auto server = new ServerHost( "localhost", 1234 );

	client.host.connect( "localhost", 1234 );

	while ( true ) {
		server.emit();
		client.emit();

		dnetSleep( 1 );
	}

	delete server;
	delete client;

	return 0;
}
