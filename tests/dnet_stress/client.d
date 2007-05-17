import dnet.client;
import std.c.time;
import std.stdio;
import std.date;

class MyClient : DnetClient {

	long start = 0;
	int packets = 0;
	int bytes = 0;

	public void onReceive(char[] data){
		if (start == 0)
			start = getUTCtime();

		if (data == "Hello world! Let's flood you!"){
			packets++;
			bytes += data.length;
		}
		else
			writefln("Unknown packet");


		if ((getUTCtime - start) / TicksPerSecond >= 1){
			writefln("Packets / Kbytes per sec % 4d / % 4.2f", packets, bytes/1024.00);
			start = getUTCtime;
			packets = 0;
			bytes = 0;
		}
	}

}


int main() {

	MyClient c = new MyClient();
	c.connect("localhost", 3333);
	while(true){
		c.send("Hello world! Let's flood you!", true);
		usleep(1000);
	}
	return 0;
}
