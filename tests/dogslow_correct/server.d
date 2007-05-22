import dogslow.all;

import std.stdio;
import std.c.time;


int main(){

	DogslowServer c = new DogslowServer();
	c.create(3333);
	while(1){
		writefln("> %s %d", c.getString(0,0,0), c.getShort(0,0,1));
		msleep(1000);
	}

	return 0;
}