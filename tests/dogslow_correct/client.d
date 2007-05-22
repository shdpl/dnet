import dogslow.all;

import std.stdio;
import std.c.time;

int main(){

	DogslowClient c = new DogslowClient();
	c.connect("localhost", 3333);

	c.setString(0,0,0,"test", true);
	c.setShort(0,0,1,1234, true);

	while(1){
		int id = c.addObject(1);
		c.setString(0,id,0,"test", true);
		c.setShort(0,id,1,1234, true);
		msleep(1000);
	}
	return 0;
}