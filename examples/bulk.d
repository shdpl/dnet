/**
	Written by Dmitry Shalkhakov but placed into public domain.

	Demonstrates DNet's fragmentation and assembly features. On each loop pass, server and client
	send each other a payload of 15_000 bytes. NOTE: Although DNet is capable of sending that much data, it is
	not intended for such use.
*/

import dnet.utils;		// these are here only to keep the example library-independent
import dnet.socket;		// you shouldn't rely on their existence
import dnet.dnet;

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
	}

	override void onDisconnect( DnetConnection c ) {
		debugPrint( "client: disconnect" );
		conn = null;
	}

	override void emit() {
		if ( conn !is null ) {
			conn.send( cast( ubyte[] )"foo" );

			ubyte[15000] extraFoo;
			conn.send( extraFoo );

			ubyte[MESSAGE_LENGTH]	msg;

			while ( true ) {
				int l = conn.receive( msg );
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
	}

	override void onDisconnect( DnetConnection c ) {
		debugPrint( "server: client disconnected" );
	}

	override void emit() {
		ubyte[MESSAGE_LENGTH]	msg;
		ubyte[15000]			extraBar;

		foreach ( c; getAll.values ) {
			if ( !c.connected ) {
				continue;
			}

			c.send( cast( ubyte[] )"bar" );
			c.send( extraBar );
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
