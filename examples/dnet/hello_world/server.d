import dnet;
import std.stdio;
import std.c.time;

int main(){
	if (!dnet_init()){
		writefln("error initializing lib");
		return 1;
	}

	if (!dnet_server_create("", 3333)){
		writefln("error creating server");
		return 1;
	}

	// listener works in different thread now
	// give him some time to work in background
	// then shutdown
	usleep(60*1000*1000);

	dnet_shutdown();

	return 0;
}