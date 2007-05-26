import std.stdio;

import dnet_new.socket;
import dnet_new.buffer;
import dnet_new.collection;

int main(){

	writefln("start");
	/*
	DnetSocket s = new DnetSocket();
	s.bind(new DnetAddress(3333));

	DnetAddress a;
	DnetBuffer b;
	while(true){
		if (s.receiveFrom(b, a) > 0){
			writefln("got %s from %s", b.getBuffer(), a.toString());
			//while(true){
			s.sendTo(new DnetBuffer("Up yours!"), a);
			//}
		}
		sleep(10);
		
	}
	*/
	DnetCollection s = new DnetCollection();
	s.bind(new DnetAddress(3333));
	while(true){
		s.emit();
		DnetBuffer buff = s.receive();
		if (buff.length() > 0)
			writefln("got %s, clients are %s", buff.getBuffer(), s.getAll().keys);
		sleep(10);
	}

	return 0;
}

