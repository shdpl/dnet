import dnet.all;
import std.c.time;
import std.stdio;
import std.date;

/**
Use reliable sending?
Experiment with this to get some interesting performance results.
*/
const bool RELIABLE = false;


/**
This slass should be able to count incoming packets/bytes per second and write it to stdout.
*/
public class MyClient : DnetClient {

	long start = 0;
	int packets = 0;
	int bytes = 0;

	/**
	Built in method we overriden.
	*/
	public void onReceive(char[] data){
		if (start == 0)
			start = getUTCtime();

		if (data == "Hello world! Let's flood you!"){
			packets++;
			bytes += data.length;
		}
		else
			writefln("Unknown packet %s", cast(ubyte[])data);


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
	if (c.connect("localhost", 3333) == false){
		writefln("Failed to connect!");
		return 0;
	}
	else
		writefln("Connected");

	while(true){
		c.send("Hello world! Let's flood you!", RELIABLE);
		msleep(1);
	}
	return 0;
}
