/**
	Written by Dmitry Shalkhakov but placed into public domain.

	Shows DNet's reliable data delivery by simulating 80% packet loss.
*/

import dnet.utils;		// these are here only to keep the example library-independent
import dnet.socket;		// you shouldn't rely on their existence
import dnet.dnet;

const LOSS_RATIO	= 0.80f;

class ClientHost : DnetHost {
	DnetConnection	conn;

	this( char[] localAddress = null, ushort localPort = 0 ) {
		super( localAddress, localPort, false );
	}

	override bool onConnectionRequest( Address from, char[] userData, ref char[] reason ) {
		debugPrint( "client: connection" );
		return false;
	}

	override void onConnectionResponse( DnetConnection c ) {
		debugPrint( "client: connected to server" );
		conn = c;
		simulatedLoss = LOSS_RATIO;	// this is set here so you won't have to wait for the connection attempt to succeed
	}

	override void onDisconnect( DnetConnection c ) {
		debugPrint( "client: disconnect" );
		conn = null;
	}

	override void emit() {
		if ( conn !is null ) {
			conn.send( cast( ubyte[] )"foobar", true );

			ubyte[MESSAGE_LENGTH]	msg;

			while ( true ) {
				int l = conn.receive( msg );
				if ( !l ) {
					break;
				}
				if ( cast( char[] )msg[0..l] == "bar" ) {
					debugPrint( "client: got bar" );
				}
			}
		}

		super.emit();
	}
}

class ServerHost : DnetHost {
	bool	sendFoo;

	this( char[] localAddress = null, ushort localPort = 0 ) {
		super( localAddress, localPort );
	}

	override bool onConnectionRequest( Address from, char[] userData, ref char[] reason ) {
		debugPrint( "server: connection from " ~ typeToUtf8( from ) );
		return true;
	}

	override void onConnectionResponse( DnetConnection c ) {
		debugPrint( "server: client connected" );
		simulatedLoss = LOSS_RATIO;	// this is set here so you won't have to wait for the connection attempt to succeed
	}

	override void onDisconnect( DnetConnection c ) {
		debugPrint( "server: client disconnected" );
	}

	override void emit() {
		ubyte[MESSAGE_LENGTH]	msg;

		foreach ( c; getAll.values ) {
			if ( !c.connected ) {
				continue;
			}

			c.send( cast( ubyte[] )"bar", true );

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

		super.emit();
	}
}

int main( char[][] args ) {
	auto client = new ClientHost;
	auto server = new ServerHost( "localhost", 1234 );

	client.connect( "localhost", 1234 );

	while ( true ) {
		server.emit();
		client.emit();
		
		dnetSleep( 1 );
	}

	delete server;
	delete client;

	return 0;
}
