import test;
import std.c.time;

int main() {

	DnetServer s = new DnetServer(3333);
	usleep(1024*1024*3);
	s.broadcast("Hello all!!!", true);
	usleep(1024*1024*100);
	return 0;

}
