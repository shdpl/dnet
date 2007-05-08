import dogslow;
import std.stdio;
import std.c.time;

int main(){
	if (!init()){
		writefln("error initializing lib");
		return 1;
	}

	if (!clientConnect("localhost", 3333)){
		writefln("error preparing resources");
		return 1;
	}

	if (!classRegistred("car"))
		registerClass("car", ["model", "price", "speed"]);
	else if (!classRegistred("tree"))
                registerClass("tree", ["age", "height", "kind"]);
	else if (!classRegistred("fish"))
		registerClass("fish", ["species", "weight", "size"]);

	shutdown();

	return 0;
}
