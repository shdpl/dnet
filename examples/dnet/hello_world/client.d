import dnet;
import std.stdio;
import std.c.time;

int main(){
	if (!dnet_init()){
		writefln("error initializing lib");
		return 1;
	}

	if (!dnet_client_connect("127.0.0.1", 3333)){
		writefln("error preparing resources");
		return 1;
	}

	dnet_client_send(cast(ubyte[])"Hello world!");

	// listener works in different thread now
	// give him some time to work in background
	// then shutdown
	usleep(10*1000*1000);



	dnet_shutdown();

	return 0;
}