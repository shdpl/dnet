import dnet.all;
import std.date;
import std.stdio;
import std.c.time;


/**
Use reliable sending?
Experiment with this to get some interesting performance results.
*/
const bool RELIABLE = true;

/**
This slass should be able to count incoming packets/bytes per second and write it to stdout.
*/
public class MyServer : DnetServer {
	long start = 0;
	int packets = 0;
	int bytes = 0;
	

	/**
	Built in method we overriden.
	*/
	public void onReceive(Address client, char[] data){
		if (start == 0)
			start = getUTCtime();

		if (data == "Hello world! Let's flood you!"){
			packets++;
			bytes += data.length;

			// send back packet
			send(client, data, RELIABLE);
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

	MyServer s = new MyServer();
	if (s.create(3333) == false){
		writefln("Failed to create server!");
		return 0;
	}
	else
		writefln("Created server!");


	// make main thread sleep forever, while server is working in background
	msleep(1000*999999);
	return 0;

}
