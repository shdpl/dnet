import dogslow_all;

import std.stdio;
import std.c.time;
import std.c.stdlib;

int main(){

	DogslowServer s = new DogslowServer();
	s.create(3333);
	while(1){
		// set random value for property 1 of object id 1 of class 1
		s.setInt(1,1,1,rand()%256, true);
		version (Windows)
			msleep(2000);
		else
			usleep(2000000);
	}

	return 0;
}
