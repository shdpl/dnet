import dnet.dnet;

version ( Tango ) {
	import tango.io.Stdout;
}
else {
	import std.stdio;
}

int main() {
	DnetConnection c = new DnetConnection();
	c.connectTo( new DnetAddress( "localhost", 3333 ) );

	uint t = 0;
	int i = 0;
	while(true){
		if ( c.connected() && c.readyToTransmit() ) {
			c.send( cast(ubyte[])"Hiya!", false );
		}
		c.emit();
		if (c.receive().length > 0) {
			i++;
		}
		t += DnetTime();

		if (t > 1000){
			version ( Tango ) {
				Stdout.format("got {0} packets per sec, ping {1}", i, c.getLatency()).newline;
			}
			else {
				writefln("got %d packets per sec, ping %d", i, c.getLatency());
			}
			t = 0;
			i = 0;
		}

		DnetSleep(1);
	}

	return 0;
}
