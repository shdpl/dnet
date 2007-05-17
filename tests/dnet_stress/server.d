import dnet.server;
import std.date;
import std.stdio;
import std.c.time;

class MyServer : DnetServer {
	long start = 0;
	int packets = 0;
	int bytes = 0;
	

	public void onReceive(Address client, char[] data){
		if (start == 0)
			start = getUTCtime();

		if (data == "Hello world! Let's flood you!"){
			packets++;
			bytes += data.length;

			// send back packet
			send(client, data, true);
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

	MyServer s = new MyServer();
	s.create(3333);

	// sleep forever
	usleep(1024*1024*999999);
	return 0;

}
