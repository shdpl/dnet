/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

/**
*/
module dogslow.client;

private import std.stdio;
private import dnet.client;
private import dogslow.obj;
private import dogslow.storage;

public class DogslowClient : DnetClient {
        private {
		int ClientId = -1;
                DogslowStorage Storage;
        }
        this(){
                super();
                Storage = new DogslowStorage();
        }
	public int getClientId(){
		return ClientId;
	}
	public void replicate(char[] data){
		writefln("client sends data %s", data);
	}
        public void registerClass(char[] class_name, char[][] class_properties){
        }
        public DogslowObject addObject(char[] class_name){
		return new DogslowObject(&Storage, &replicate, class_name, 1);
        }
        public DogslowObject getObject(char[] class_name, int object_id){
		return null;
        }
        public DogslowObject getObjects(char[] class_name){
		return null;
        }
        public void deleteObject(char[] class_name, int object_id){
        }
        public void deleteObject(DogslowObject dogslow_object){
        }
}

