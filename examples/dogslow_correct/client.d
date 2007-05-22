import dogslow_all;

import std.stdio;
import std.c.time;

int main(){

	DogslowClient c = new DogslowClient();
	c.connect("localhost", 3333);

	while(1){
		writefln("value is %d", c.getInt(1,1,1));
		version (Windows)
			msleep(50);
		else
			usleep(50*1000);
	}
	return 0;
}
