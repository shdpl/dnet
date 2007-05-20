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

/**
Synchronized object. You chould *not* create it by yourself, but use getObject() and createObject() 
methods of DogslowClient & DogslowServer.
*/
class DogslowObject {


	private {
		DogslowHost Host;
		char[] Class;
		int Id;
	}


	this(DogslowHost host, char[] class_name, int object_id){
		Host = host;
		Class = class_name;
		Id = object_id;
	}

	~this(){
	}


	/**
	Gets class name.
	*/
	char[] getClass() {
		return Class;
	}


	/**
	Gets object id.
	*/
	int getId() {
		return Id;
	}


	/**
	*/
	void setString(char[] property_name, char[] value, bool replicate){
		Host.setString(Class, Id, property_name, value, replicate);
	}


	/**
	*/
	char[] getString(char[] property_name){
		return Host.getString(Class, Id, property_name);
	}



}
