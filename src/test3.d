import test;
import std.c.time;

int main() {

	DnetServer s = new DnetServer(3333);
	s.start();
	usleep(1024*1024*100);
	return 0;

}