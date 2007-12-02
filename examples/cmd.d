/**
	Written by Dmitry Shalkhakov but placed into public domain.
*/

import dnet.utils;		// these are here only to keep the example library-independent
import dnet.socket;		// you shouldn't rely on their existence
import dnet.dnet;

class ClientHost {
	DnetHost		host;

	this( char[] localAddress = null, ushort localPort = 0 ) {
		host = new DnetHost( 33600, 33600, localAddress, localPort, false );
		host.connectionRequest = &handleConnectionRequest;
		host.connection = &handleConnection;
		host.command = &handleCommand;
		host.messageSend = &handleMessageSend;
		host.messageReceive = &handleMessageReceive;
	}

	void emit() {
		host.emit();
	}

	bool handleConnectionRequest( Address from, char[] userData, ref char[] reason ) {
		debugPrint( "client: connection" );
		return false;
	}

	void handleConnection( DnetConnection c ) {
		debugPrint( "client: connected to server" );
	}

	void handleCommand( DnetConnection c, char[] cmd, char[][] args ) {
		if ( args[0] == "bar" ) {
			debugPrint( "client: got bar" );
		}
	}

	void handleMessageSend( DnetConnection c ) {
		c.sendCommand( "foobar", false );
	}

	void handleMessageReceive( DnetConnection c ) {
		ubyte[MESSAGE_LENGTH]	msg;

		while ( true ) {
			int l = c.receive( msg );
			if ( !l ) {
				break;
			}
		}
	}
}

class ServerHost {
	DnetHost	host;

	this( char[] localAddress = null, ushort localPort = 0 ) {
		host = new DnetHost( 33600, 33600, localAddress, localPort );
		host.connectionRequest = &handleConnectionRequest;
		host.connection = &handleConnection;
		host.command = &handleCommand;
		host.messageSend = &handleMessageSend;
		host.messageReceive = &handleMessageReceive;
	}

	void emit() {
		host.emit();
	}

	bool handleConnectionRequest( Address from, char[] userData, ref char[] reason ) {
		debugPrint( "server: connection from " ~ typeToUtf8( from ) );
		return true;
	}

	void handleConnection( DnetConnection c ) {
		debugPrint( "server: client connected" );
	}

	void handleCommand( DnetConnection c, char[] cmd, char[][] args ) {
		if ( args[0] == "foobar" ) {
			debugPrint( "server: got foobar" );
		}
	}

	void handleMessageSend( DnetConnection c ) {
		c.sendCommand( "bar", false );
	}

	void handleMessageReceive( DnetConnection c ) {
		ubyte[MESSAGE_LENGTH]	msg;

		while ( true ) {
			auto l = c.receive( msg );
			if ( !l ) {
				break;
			}
		}
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
