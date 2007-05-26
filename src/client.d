import std.stdio;

import dnet_new.socket;
import dnet_new.buffer;
import dnet_new.connection;

int main(){

	DnetConnection c = new DnetConnection(new DnetAddress(3333));
	c.send(new DnetBuffer("Hello world!"));
	char[] buff;
	while(true){
		c.emit();
		buff = c.receive().getBuffer();
		if (buff.length > 0)
			writefln("got reply %s", buff);
		sleep(1);
	}


/*
	DnetSocket s = new DnetSocket();
	while (true){
		s.sendTo(new DnetBuffer("Hello world!"), new DnetAddress(3333));
		int size;
		DnetBuffer b;
		DnetAddress a;
		size = s.receiveFrom(b, a);
		if (size >0)
			writefln("got %s from %s", b.getBuffer(), a.toString());
		sleep(10);
	}
*/

	return 0;
}

