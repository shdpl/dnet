import dnet.dnet;
import std.stdio;

int main() {

	DnetConnection c = new DnetConnection();
	c.connectToServer( new DnetAddress( "localhost", 3333 ) );

	uint t = 0;
	int i = 0;
	while(true){
		c.send( "Hiya!", false );
		c.emit();
		if (c.receive().length > 0) {
			i++;
		}
		t += DnetTime();

		if (t > 1000){
			writefln("got %d packets per sec", i);
			t = 0;
			i = 0;
		}

		DnetSleep(1);
	}

	return 0;
}
