import test;
import std.c.time;

int main() {

	DnetClient c = new DnetClient("localhost", 3333);
	c.send("Hello world!", true);
	c.send("Here I am again....", false);
	c.send("Are you there....?", true);
	usleep(1024*1024*10);
	return 0;
}
