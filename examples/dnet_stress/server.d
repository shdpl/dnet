
version ( Tango ) {
	import tango.io.Stdout;
}
else {
	import std.stdio;
}

import dnet.dnet;

int main() {
	DnetCollection s = new DnetCollection( new DnetAddress("localhost", 3333), new DnetAddress("localhost", 3003) );
	while(true){
		s.emit();
		if (s.getAll().length > 0) {
			s.broadcast(cast( ubyte[] )"Leave me alone!", false);
			s.broadcast(cast( ubyte[] ) "I mean it!", true );
		}
		DnetSleep(1);
	}
	return 0;
}
