/**
	Written by Dmitry Shalkhakov but placed into public domain.
	Shows host enumeration functions.
*/

import dnet.utils;		// these are here only to keep the example library-independent
import dnet.socket;		// you shouldn't rely on their existence
import dnet.dnet;

class ServerHost {
	DnetHost	host;

	this( char[] localAddress = null, ushort localPort = 0 ) {
		host = new DnetHost( 33600, 33600, localAddress, localPort );
		host.enumerationRequest = &handleEnumerationRequest;
	}

	void emit() {
		host.emit();
	}

	int handleEnumerationRequest( char[] userInfo, char[] hostInfo ) {
		const char[]	info = "welcome to gothdom!";
		debugPrint( "server: got enumeration request: " ~ userInfo );
		hostInfo[0..info.length] = info[];
		return info.length;
	}
}

int main( char[][] args ) {
	auto server = new ServerHost( "localhost", 1234 );

	while ( true ) {
		server.emit();

		dnetSleep( 1 );
	}

	delete server;

	return 0;
}
