/**
	Written by Dmitry Shalkhakov but placed into public domain.

	Shows DNet's reliable data delivery by simulating 25% packet loss.
*/

import dnet.utils;		// these are here only to keep the example library-independent
import dnet.socket;		// you shouldn't rely on their existence
import dnet.dnet;

const LOSS_RATIO	= 0.25f;

class ClientHost {
	DnetHost		host;

	this( char[] localAddress = null, ushort localPort = 0 ) {
		host = new DnetHost( 33600, 33600, localAddress, localPort, false );
		host.connectionRequest = &handleConnectionRequest;
		host.connection = &handleConnection;
		host.messageSend = &handleMessageSend;
		host.messageReceive = &handleMessageReceive;
	}

	bool handleConnectionRequest( Address from, char[] userData, ref char[] reason ) {
		debugPrint( "client: connection" );
		return false;
	}

	void handleConnection( DnetConnection c ) {
		debugPrint( "client: connected to server" );
		host.lossRatio = LOSS_RATIO;	// this is set here so you won't have to wait for the connection attempt to succeed
	}

	void handleMessageSend( DnetConnection c ) {
		c.send( cast( ubyte[] )"foobar", true );
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
		host.lossRatio = LOSS_RATIO;	// this is set here so you won't have to wait for the connection attempt to succeed
	}

	void handleMessageSend( DnetConnection c ) {
		c.send( cast( ubyte[] )"bar", true );
	}

	void handleMessageReceive( DnetConnection c ) {
		ubyte[MESSAGE_LENGTH]	msg;

		while ( true ) {
			auto l = c.receive( msg );
			if ( !l ) {
				break;
			}
			if ( cast( char[] )msg[0..l] == "foobar" ) {
				debugPrint( "server: got foobar" );
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
