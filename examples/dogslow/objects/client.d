import dogslow;
import std.stdio;
import std.c.time;
import std.string;
import std.random;

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
                // we assume there is exactly one fish - our fish :)
                fish = getObjects("fish")[0];
                fish.setString("name", names[cast(int)(rand() % names.length)]);

                while(true){
                        writefln("Fish with id %d has name %s", fish.getId(), fish.getString("name"));
                        usleep(1*1000*1000);
                }
        }

        shutdown();

	return 0;
}
