import dogslow;
import std.stdio;
import std.c.time;

int main(){
	if (!dogslow.init()){
		writefln("error initializing lib");
		return 1;
	}

	if (!dogslow.serverCreate("localhost", 3333)){
		writefln("error creating server");
		return 1;
	}


        registerClass("fish", ["name"]);
        DogObject a = addObject("fish");
        a.setString("name", "Flipper");

        while(true){
                writefln("Fish with id %d has name %s", a.getId(), a.getString("name"));
                usleep(1*1000*1000); // wait for one second
        }

        dogslow.shutdown();

	return 0;
}
