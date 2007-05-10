import dogslow;
import std.stdio;
import std.c.time;
import std.string;
import std.random;
import std.math;

int main(){
	if (!init()){
		writefln("error initializing lib");
		return 1;
	}

	if (!clientConnect("localhost", 3333)){
		writefln("error preparing resources");
		return 1;
	}

        char[][] names = ["Joe", "Great White", "Willy", "Merlin"];
        DogObject fish;

        if (classRegistred("fish")){
		if (getObjects("fish").length == 1){
	                // we assume there is exactly one fish - our fish :)
        	        fish = getObjects("fish")[0];

			
	                while(true){
				uint r = rand();
				fish.setString("name", names[(r-cast(uint)(r/4)*4)]);
        	                writefln("Fish with id %d has name %s", fish.getId(), fish.getString("name"));
                	        usleep(1*1000*1000);
	                }
		}
		else
			writefln("no object found");
        }
	else
		writefln("fish not registred");
        shutdown();

	return 0;
}
