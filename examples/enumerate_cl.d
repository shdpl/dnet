/**
	Written by Dmitry Shalkhakov but placed into public domain.
	Shows host enumeration functions.
*/

import dnet.utils;		// these are here only to keep the example library-independent
import dnet.socket;		// you shouldn't rely on their existence
import dnet.dnet;

class ClientHost {
	DnetHost		host;

	this( char[] localAddress = null, ushort localPort = 0 ) {
		host = new DnetHost( 33600, 33600, localAddress, localPort, false );
		host.enumerationResponse = &handleEnumerationResponse;
	}

	void emit() {
		host.emit();
	}

	void handleEnumerationResponse( char[] hostInfo, Address from ) {
		debugPrint( "client: got host info from " ~ typeToUtf8( from ) ~ " :" ~ hostInfo );
	}
}

int main( char[][] args ) {
	auto client = new ClientHost;

	client.host.enumerateHosts( "howdy?", new IPv4Address( "255.255.255.255", 1234 ) );

	while ( true ) {
		client.emit();
		
		dnetSleep( 1 );
	}

	delete client;

	return 0;
}
