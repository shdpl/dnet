/**
	Written by Dmitry Shalkhakov but placed into public domain.
*/

import tango.io.Stdout;

import dnet.utils;		// these are here only to keep the example library-independent
import dnet.socket;		// you shouldn't rely on their existence
import dnet.dnet;
import dnet.time;

class ClientHost {
	DnetHost		host;

	this( char[] localAddress = null, ushort localPort = 0 ) {
		host = new DnetHost( 33600, 33600, localAddress, localPort, false );
		host.connectionRequest = &handleConnectionRequest;
		host.connection = &handleConnection;
		host.messageSend = &handleMessageSend;
		host.messageReceive = &handleMessageReceive;

		host.simLatency = 100;
		host.simJitter = 50;
		Stdout.formatln( "client: set latency to {0}, jitter to {1}", host.simLatency, host.simJitter );
	}

	bool handleConnectionRequest( Address from, char[] userData, ref char[] reason ) {
		debugPrint( "client: connection" );
		return false;
	}

	void handleConnection( DnetConnection c ) {
		debugPrint( "client: connected to server" );
	}

	void handleMessageSend( DnetConnection c ) {
		c.send( cast( ubyte[] )"foo" );
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

	void handleMessageSend( DnetConnection c ) {
		c.send( cast( ubyte[] )"bar" );
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
	auto nextPrintTime = currentTime();
	auto client = new ClientHost;
	auto server = new ServerHost( "localhost", 1234 );

	client.host.connect( "localhost", 1234 );

	while ( true ) {
		if ( client.host.getAll.values.length && client.host.getAll.values[0] !is null ) {
			if ( nextPrintTime < currentTime() ) {
				Stdout( client.host.getAll.values[0].latency ).newline;
				nextPrintTime = currentTime + 2000;
			}
		}

		server.emit();
		client.emit();

		dnetSleep( 1 );
	}

	delete server;
	delete client;

	return 0;
}
