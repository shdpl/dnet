/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

/**
*/
module dogslow.object;

private import std.stdio;
private import std.string;
private import std.c.time;
private import std.random;


///
class DogslowObject {


	private {
		DogslowHost Host;
		DogslowStorage Storage;
		char[] Class;
		ushort Id;
	}


///
	this(DogslowHost host, char[] class_name, int object_id){
		Host = host;
		Class = class_name;
		Id = object_id;
	}


///
	this(char[] class_name, int object_id){
		Class = class_name;
		Id = object_id;
	}


///
	~this(){
	}


///
	char[] getClass() {
		return Class;
	}


///
	int getId() {
		return Id;
	}


///
	void setString(char[] property_name, char[] value, bool replicate=true){
		/*
		if (IsServer){
                        Cache[className][objectId][property_name] = cast(ubyte[])value;

			serverBroadcast([cast(ubyte)PacketType.SET_PROP, cast(ubyte)objectId] ~ cast(ubyte[])(format("%s %s ", className, property_name)) ~ cast(ubyte[])value);

		}
		else {
			dnet_client_send([cast(ubyte)PacketType.SET_PROP, cast(ubyte)objectId] ~ cast(ubyte[])(format("%s %s ", className, property_name)) ~ cast(ubyte[])value);
		}
		*/
	}


///
	void setByte(char[] property_name, byte value, bool replicate=true){
	}


///
	void setShort(char[] property_name, short value, bool replicate=true){
	}


///
	void setInt(char[] property_name, int value, bool replicate=true){
	}


///
	void setFloat(char[] property_name, float value, bool replicate=true){
	}


///
	void setVector3f(char[] property_name, float[3] value, bool replicate=true){
	}


///
	void setPointer(char[] property_name, void* value){
	}


///	
	char[] getString(char[] property_name){
		return cast(char[])Cache[className][objectId][property_name];
	}


///
	byte getByte(char[] property_name){
		return 0;
	}


///
	short getShort(char[] property_name){
		return 0;
	}


///
	int getInt(char[] property_name){
		return 0;
	}


///
	float getFloat(char[] property_name){
		return 0.0;
	}


///
	float[] getVector3f(char[] property_name){
		return [0,0,0];
	}


///
	void* getPointer(char[] property_name){
		return null;
	}


}
