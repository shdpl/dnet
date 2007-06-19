import dnet.dnet;
import std.stdio;

int main() {

	DnetCollection s = new DnetCollection();
	s.bind(new DnetAddress("localhost", 3333), new DnetAddress("localhost", 3003));
	while(true){
		s.emit();
		if (s.getAll().length > 0) {
			s.broadcast("Leave me alone!", false);
			s.broadcast( "I mean it!", true );
		}
		DnetSleep(1);
	}
	return 0;
}
