/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

/**
*/
module dogslow.storage;

private import std.stdio;
private import std.string;
private import std.c.stdlib;
private import std.c.string;

/**
Base unit for storage. 
Convenient to cast to bytearray for network transfer.
*/
struct Atom {
	void* ptr = null; /// pointer to data in memory
	int size = 0; /// number of bytes in data
}

/**
Class that stores objects with their properties in local memory. 
All data is stored as void* and converted on each read/write.
This baby does a lot of malloc(), memcpy() and free()-ing and that is all what it does.

TODO:
Firther speed/memory usage optimizations?
*/
class DogslowStorage {


	private {
		Atom[int][int][int] Cache; 
	}


	this(){
	}


	~this(){
	}


	/**
	*/
	//public int registerClass(char[] class_name, char[][]class_properties){
	//	int class_id = -1;
	//	if (ClassName.length < 256 && (class_name in ClassNameToId) == null && class_properties.length <= 256){
	//		class_id = ClassName.length;
	//		ClassName[class_id] = class_name;
	//		ClassNameToId[class_name] = class_id;
	//		foreach(uint property_id, char[] property_name; class_properties){
	//			PropertyName[class_id][property_id] = property_name;
	//			PropertyNameToId[class_id][property_name] = property_id;
	//		}
//
//		}
//		return class_id;
//	}

//	private int classNameToId(char[] class_name){
//		if ((class_name in ClassNameToId) == null)
//			return -1;
//		else
//			return ClassNameToId[class_name];
//	}

//	private int propertyNameToId(char[] class_name, char[] property_name){
//		if ((property_name in PropertyNameToId[classNameToId(class_name)]) == null)
//			return -1;
//		else
//			return PropertyNameToId[classNameToId(class_name)][property_name];
//	}


	public void del(){
	}

	public void del(int class_id){
		try {
			Cache.remove(class_id);
			// must free pointers too
		}
		catch {}
	}

	public void del(int class_id, int object_id){
		try {
			Cache[class_id].remove(object_id);
			// must free pointers too
		}
		catch {}
	}

	public void del(int class_id, int object_id, int property_id){
		try {
			free(Cache[class_id][object_id][property_id].ptr);
			Cache[class_id][object_id].remove(property_id);
		}
		catch {}
	}


	//public void setRaw(char[] class_name, int object_id, char[] property_name, void* value, uint size){
	//	int class_id = classNameToId(class_name);
	//	int property_id = propertyNameToId(class_name, property_name);
	//	if (class_id == -1 || property_id == -1)
	//		return;
	//	setRaw(class_id, object_id, property_id, value, size);
	//}

	public void setRaw(int class_id, int object_id, int property_id, void* value, uint size){
		del(class_id, object_id, property_id);
		Atom a;
		a.size = size;
		if (size > 0){
			a.ptr = malloc(size);
			memcpy(a.ptr, value, size);
		}
		Cache[class_id][object_id][property_id] = a;
	}


	//public Atom getRaw(char[] class_name, int object_id, char[] property_name){
	//	int class_id = classNameToId(class_name);
	//	int property_id = propertyNameToId(class_name, property_name);
	//	Atom a;
	//	// value migh not be set yet so an exception might be raised
	//	try {
	//		a = Cache[class_id][object_id][property_id];
	//	}
	//	catch {
	//		
	//	}
	//	return a;
	//}

	public Atom getRaw(int class_id, int object_id, int property_id){
		Atom a;
		try {
			a = Cache[class_id][object_id][property_id];
		}
		catch {}
		return a;
	}

	public int[] getClasses(){
		int[] all;
		all.length = Cache.length;
		foreach(int i, int class_id; Cache.keys){
			all[i] = class_id;
		}
		return all;
	}


	public int[] getObjects(int class_id){
		int[] all;
		if ((class_id in Cache) != null){
			all.length = Cache[class_id].length;
			foreach(int i, int object_id; Cache[class_id].keys){
				all[i] = object_id;
			}
		}
		return all;
	}

	public int[] getProperties(int class_id, int object_id){
		int[] all;
		if ((class_id in Cache) != null && (object_id in Cache[class_id]) ){
			all.length = Cache[class_id][object_id].length;
			foreach(int i, int property_id; Cache[class_id][object_id].keys){
				all[i] = property_id;
			}
		}
		return all;
	}


	public void setString(int class_id, int object_id, int property_id, char[] value){
		// dynamic arrays are stored as static to save space
		// we skip dynamic array 8 byte header (value.sizeof), we store data only
		setRaw(class_id, object_id, property_id, value.ptr, value.length);
	}


	/**
	*/
	//public void setString(char[] class_name, int object_id, char[] property_name, char[] value){
	//	// dynamic arrays are stored as static to save space
	//	// we skip dynamic array 8 byte header (value.sizeof), we store data only
	//	setRaw(class_name, object_id, property_name, value.ptr, value.length);
	//}

	/**
	*/
	public char[] getString(int class_id, int object_id, int property_id){
		Atom a = getRaw(class_id, object_id, property_id);

		if (a.size == 0)
			return "";
		else {
			// we get stored array and converrt it to dynamic array
			char[] buff;
			buff.length = a.size;
			memcpy(buff.ptr, a.ptr, a.size);
			return buff;
		}
	}


	/**
	*/
	//public void setInt(char[] class_name, int object_id, char[] property_name, int value){
	//	setRaw(class_name, object_id, property_name, &value, 4);
	//}


	/**
	*/
	
	//public int getInt(char[] class_name, ushort object_id, char[] property_name){
	//	Atom a = getRaw(class_name, object_id, property_name);
	//	if (a.size == 0)
	//		return 0;
	//	else
	//		return *(cast(int*)a.ptr);
	//}
	

	unittest {
	/*	DogslowStorage s = new DogslowStorage();

		// register some classess
		assert(s.classNameToId("tree") == -1);
		assert(s.classNameToId("car") == -1);
		s.registerClass("car", ["model", "speed", "price"]);
		assert(s.classNameToId("car") == 0);
		assert(s.propertyNameToId("car", "model") == 0);
		assert(s.propertyNameToId("car", "speed") == 1);
		assert(s.propertyNameToId("car", "price") == 2);

		s.registerClass("fish", ["species", "weight", "age"]);
		assert(s.classNameToId("fish") == 1);
		assert(s.propertyNameToId("fish", "species") == 0);
		assert(s.propertyNameToId("fish", "weight") == 1);
		assert(s.propertyNameToId("fish", "age") == 2);

		// store some values
		s.setString("car", 0, "model", "ferrari");
		s.setInt("car", 0, "price",  123000);

		// test those values
		assert(s.getString("car", 0, "model") == "ferrari");
		assert(s.getInt("car", 0, "price") == 123000);


		// memory leak test. should eat about 500mb of RAM very fast if there is a leak
		// uncomment if you like
		
		//for (int i = 0; i < 500*1024; i++){
		//	s.setString("car", 0, "model", repeat("x", 1024));
		//	assert(s.getString("car", 0, "model") == repeat("x", 1024));
		//}
		
*/
		writefln("DogslowStorage unittest PASS");

	}

}
