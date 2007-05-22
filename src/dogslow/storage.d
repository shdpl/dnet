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


	public void del(){
		try {
			foreach(int class_id; Cache.keys){
				del(class_id);
			}
		}
		catch {}
	}

	public void del(int class_id){
		try {
			foreach(int object_id; Cache[class_id].keys){
				del(class_id, object_id);
			}
			Cache.remove(class_id);
		}
		catch {}
	}

	public void del(int class_id, int object_id){
		try {
			foreach(int property_id; Cache[class_id][object_id].keys){
				del(class_id, object_id, property_id);
			}
			Cache[class_id].remove(object_id);
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


	/**
	*/
	public void setString(int class_id, int object_id, int property_id, char[] value){
		// dynamic arrays are stored as static to save space
		// we skip dynamic array 8 byte header (value.sizeof), we store data only
		setRaw(class_id, object_id, property_id, value.ptr, value.length);
	}


	/**
	*/
	public void setByte(int class_id, int object_id, int property_id, char value){
		setRaw(class_id, object_id, property_id, &value, 1);
	}


	/**
	*/
	public void setShort(int class_id, int object_id, int property_id, short value){
		setRaw(class_id, object_id, property_id, &value, 2);
	}


	/**
	*/
	public void setInt(int class_id, int object_id, int property_id, int value){
		setRaw(class_id, object_id, property_id, &value, 4);
	}


	/**
	*/
	public void setFloat(int class_id, int object_id, int property_id, float value){
		setRaw(class_id, object_id, property_id, &value, 4);
	}


	/**
	*/
	public void setVector3f(int class_id, int object_id, int property_id, float[3] value){
		setRaw(class_id, object_id, property_id, value.ptr, 12);
	}



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
	public char getByte(int class_id, int object_id, int property_id){
		Atom a = getRaw(class_id, object_id, property_id);

		if (a.size == 1)
			return *(cast(char*)a.ptr);
		else
			return 0;
	}

	/**
	*/
	public short getShort(int class_id, int object_id, int property_id){
		Atom a = getRaw(class_id, object_id, property_id);

		if (a.size == 2)
			return *(cast(short*)a.ptr);
		else
			return 0;
	}


	/**
	*/
	public int getInt(int class_id, int object_id, int property_id){
		Atom a = getRaw(class_id, object_id, property_id);

		if (a.size == 4)
			return *(cast(int*)a.ptr);
		else
			return 0;
	}

	/**
	*/
	public float getFloat(int class_id, int object_id, int property_id){
		Atom a = getRaw(class_id, object_id, property_id);

		if (a.size == 4)
			return *(cast(float*)a.ptr);
		else
			return 0;
	}

	/**
	*/
	public float[] getVector3f(int class_id, int object_id, int property_id){
		Atom a = getRaw(class_id, object_id, property_id);

		if (a.size == 12){
			float[] buff;
			buff.length = 3;
			memcpy(buff.ptr, a.ptr, 12);
			return buff;
		}
		else
			return cast(float[])[0, 0, 0];
	}

	unittest {

		DogslowStorage s = new DogslowStorage();

		// unique class id for CAR class
		int CAR = 1;

		// unique property id's for CAR class
		int MODEL = 0;
		int DRIVE = 1;
		int YEAR = 2;
		int WEIGHT = 3;
		int PRICE = 4;
		int POSITION = 5;

		// store some values
		s.setString(CAR, 0, MODEL, "ferrari");
		s.setByte(CAR, 0, DRIVE, 1);
		s.setShort(CAR, 0, YEAR, 2007);
		s.setInt(CAR, 0, WEIGHT, 1600);
		s.setFloat(CAR, 0, PRICE, 123000.50);
		s.setVector3f(CAR, 0, POSITION, cast(float[])[3,44,1]);

		// test those values
		assert(s.getString(CAR, 0, MODEL) == "ferrari");
		assert(s.getByte(CAR, 0, DRIVE) == 1);
		assert(s.getShort(CAR, 0, YEAR) == 2007);
		assert(s.getInt(CAR, 0, WEIGHT) == 1600);
		assert(s.getFloat(CAR, 0, PRICE) == 123000.50);
		assert(s.getVector3f(CAR, 0, POSITION) == cast(float[])[3,44,1]);

		writefln("DogslowStorage unittest PASS");

	}

}
