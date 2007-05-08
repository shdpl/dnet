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


	writefln("Listing all registered classess with their registered properties...");
	while(true){
		writefln("Total registered classess: %d", getClassess().length);
		foreach(char[] class_name; getClassess()){
			writef("\t" ~ class_name ~ " =>");
			foreach(char[] prop_name; getProperties(class_name)){
				writef(" " ~ prop_name);
			}
		}
		writefln("");
		usleep(1*1000*1000); // wait for one second
	}

	dogslow.shutdown();

	return 0;
}
