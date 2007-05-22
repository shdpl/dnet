import dnet_all;
import std.date;
import std.stdio;
import std.c.time;
import std.string;


public class MyServer : DnetServer {

	int i = 0;

	public void onReceive(Address client, char[] data){
		if (data == format("packet %d", i)){
			writefln("got right packet id %d", i);
			i++;
		}
		else
			writefln("Unordered packet %s", data);

		send(client, data, true);
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
