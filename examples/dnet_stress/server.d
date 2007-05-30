import dnet.dnet;
import std.stdio;

int main() {

	DnetCollection s = new DnetCollection();
	s.bind(new DnetAddress(3333));
	while(true){
		s.emit();
		//if (s.getAll().length > 0)
		//	s.broadcast(new DnetBuffer("Leave me alone!"));
		sleep(1000);
	}
	return 0;
}
