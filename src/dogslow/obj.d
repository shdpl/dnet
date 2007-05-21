/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

/**
*/
module dogslow.obj;

private import std.stdio;
private import std.c.string;
private import dogslow.storage;

/**
Synchronized object. You chould *not* create it by yourself, but use getObject() and createObject() 
methods of DogslowClient & DogslowServer.
*/
public class DogslowObject {

	private {
		void delegate(char[]) Replicator;
		DogslowStorage Storage;
		char[] Class;
		int Id;
	}


	/**
	Do not call constructor yourself. 
	Do not create object of this class directly.
	Use getObject() or createObject() instead.
	*/
	this(DogslowStorage* storage, void delegate(char[]) replicator, char[] class_name, int object_id){
		Storage = *storage;
		Replicator = replicator;
		Class = class_name;
		Id = object_id;
		assert(Sender != null);
	}

	~this(){
	}


	/**
	Gets class name.
	*/
	public char[] getClass() {
		return Class;
	}


	/**
	Gets object id.
	*/
	public int getId() {
		return Id;
	}


	/**
	*/
	private void doReplicate(char[] property_name){
		Atom a = Storage.getRaw(Class, Id, property_name);
		char[] buff;
		buff.length = a.size;
		memcpy(buff.ptr, a.ptr, a.size);
		Replicator(buff); 
	}


	/**
	*/
	public void setString(char[] property_name, char[] value, bool replicate){
		Storage.setString(Class, Id, property_name, value);
		if (replicate)
			doReplicate(property_name);
	}


	/**
	*/
	public char[] getString(char[] property_name){
		return Storage.getString(Class, Id, property_name);
	}


        /**
        */
        public void setInt(char[] property_name, int value, bool replicate){
                Storage.setInt(Class, Id, property_name, value);
                if (replicate)
                        doReplicate(property_name);
        }


        /**
        */
        public int getInt(char[] property_name){
                return Storage.getInt(Class, Id, property_name);
        }


	unittest {
	}


}
