import dnet_all;
import std.c.time;
import std.stdio;
import std.date;
import std.string;

public class MyClient : DnetClient {

	int i = 0;

	public void onReceive(char[] data){
		if (data == format("packet %d", i)){
			writefln("got right packet id %d", i);
			i++;
		}
		else
			writefln("Unordered packet %s", data);
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

	for (int i = 0; i < 10000; i++){
		c.send(format("packet %d", i), true);
		msleep(50);
	}
	return 0;
}
