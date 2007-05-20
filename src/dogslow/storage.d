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
Class that stores objects with their properties in local memory. 
All data is stored as void* and converted on each read/write.
This baby does a lot of malloc(), memcpy() and free()-ing and that is all what it does.

TODO:
Firther speed/memory usage optimizations?
*/
class DogslowStorage {


	private {
		//DogslowHost Host;

		int[char[]] ClassNameToId;
		char[][int] ClassName;

		int[char[]][int] PropertyNameToId; // property_id[class_id][property_name]
		char[][int][int] PropertyName; // property_name[class_id][property_id]

		void*[int][int][int] Cache; 
	}


	this(){
	}


	~this(){
	}


	/**
	*/
	public void registerClass(char[] class_name, char[][]class_properties){
		if (ClassName.length < 256 && (class_name in ClassNameToId) == null && class_properties.length <= 256){
			int class_id = ClassName.length;
			ClassName[class_id] = class_name;
			ClassNameToId[class_name] = class_id;
			foreach(uint property_id, char[] property_name; class_properties){
				PropertyName[class_id][property_id] = property_name;
				PropertyNameToId[class_id][property_name] = property_id;
			}

		}
	}

	private int classNameToId(char[] class_name){
		if ((class_name in ClassNameToId) == null)
			return -1;
		else
			return ClassNameToId[class_name];
	}

	private int propertyNameToId(char[] class_name, char[] property_name){
		if ((property_name in PropertyNameToId[classNameToId(class_name)]) == null)
			return -1;
		else
			return PropertyNameToId[classNameToId(class_name)][property_name];
	}

	private void setRaw(char[] class_name, int object_id, char[] property_name, void* value, uint size){
		int class_id = classNameToId(class_name);
		int property_id = propertyNameToId(class_name, property_name);
		if (class_id == -1 || property_id == -1)
			return;

		// value migh not be set yet so an exception might be raised
		try {
			if (Cache[class_id][object_id][property_id] != null)
				free(Cache[class_id][object_id][property_id]);
		}
		catch {
		}

		void* p = malloc(size);
		memcpy(p, value, size);
		Cache[class_id][object_id][property_id] = p;
	}


	private void* getRaw(char[] class_name, int object_id, char[] property_name){
		int class_id = classNameToId(class_name);
		int property_id = propertyNameToId(class_name, property_name);
		void* p;
		// value migh not be set yet so an exception might be raised
		try {
			p = Cache[class_id][object_id][property_id];
		}
		catch {
			p = null;
		}
		return p;
	}


	/**
	*/
	public void setString(char[] class_name, int object_id, char[] property_name, char[] value){
		setRaw(class_name, object_id, property_name, &value, value.sizeof + value.length);
	}

	/**
	*/
	public char[] getString(char[] class_name, ushort object_id, char[] property_name){
		void* p = getRaw(class_name, object_id, property_name);
		if (p == null)
			return "";
		else
			return *(cast(char[]*)p);
	}


	/**
	*/
	public void setInt(char[] class_name, int object_id, char[] property_name, int value){
		setRaw(class_name, object_id, property_name, &value, 4);
	}


	/**
	*/
	
	public int getInt(char[] class_name, ushort object_id, char[] property_name){
		void* p = getRaw(class_name, object_id, property_name);
		if (p == null)
			return 0;
		else
			return *(cast(int*)p);
	}
	

	unittest {
		DogslowStorage s = new DogslowStorage();

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
		

		writefln("DogslowStorage unitest PASS");

	}

}
