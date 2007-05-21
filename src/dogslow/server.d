/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

/**
*/
module dogslow.server;

private import std.stdio;
private import std.string;
private import std.c.time;
private import std.c.stdlib;

private import std.thread;


private import dnet.server;
private import dogslow.storage;

const int CLIENTID = 0;
const int REPLICATE = 1;
const int UPLOADED = 2;
const int DELETE = 3;

// predefined object
const int CLIENT = 0;
// predefined property
const int ADDRESS = 0;


public class DogslowServer : DnetServer {


	private {
                DogslowStorage Storage;
        }


        this(){
                super();
                Storage = new DogslowStorage();
		srand(999999);
        }

	public bool onConnect(Address client){
		foreach(int class_id; Storage.getClasses){
			foreach(int object_id; Storage.getObjects(class_id)){
				foreach(int property_id; Storage.getProperties(class_id, object_id)){
					char[] buff = Storage.getString(class_id, object_id, property_id);
					if (buff.length > 0){
						send(client, 
							cast(char[])[REPLICATE, class_id, object_id/256, object_id%256, property_id] ~ 
							buff, 
						true);
					}
				}
			}
		}
		int client_id = addObject(CLIENT);
		writefln(">>>>>>>> %d", client_id);
		setString(CLIENT, client_id, 0, client.toString(), true);
		send(client, cast(char[])[CLIENTID, client_id/256, client_id%256], true);
		send(client, cast(char[])[UPLOADED], true);
		return true;
	}

	public void onReceive(Address client, char[] data){
		writefln("got > %s", cast(ubyte[])data);
		switch (data[0]){
			case REPLICATE:
				int class_id = data[1];
				int object_id = data[2]*256 + data[3];
				int property_id = data[4];
				Storage.setRaw(class_id, object_id, property_id, data.ptr + 5, data.length - 5);
				broadcast(data, true);
				break;
			case DELETE:
				int class_id = data[1];
				int object_id = data[2]*256 + data[3];
				Storage.del(class_id, object_id);
				broadcast(data, true);
				break;
			default:
		}
	}

	public void onDisconnect(Address client){
		foreach(int client_id; getObjects(CLIENT)){
			if (getString(CLIENT, client_id, ADDRESS) == client.toString()){
				deleteObject(CLIENT, client_id);
			}
		}
	}

	public int addObject(int class_id){
		//return getObjects(class_id).length;
		return rand() % (256*256);
	}

	public int[] getObjects(int class_id){
		return Storage.getObjects(class_id);
	}

	public void deleteObject(int class_id, int object_id){
		char[] buff;
		buff = cast(char[])[DELETE, class_id, object_id/256, object_id%256];
		broadcast(buff, true);
		Storage.del(class_id, object_id);
	}

	public void setString(int class_id, int object_id, int property_id, char[] value, bool replicate){
		if (replicate){
			char[] buff;
			buff = cast(char[])[REPLICATE, class_id, object_id/256, object_id%256, property_id] ~ value;
			broadcast(buff, true);
		}
		Storage.setString(class_id, object_id, property_id, value);
	}

	public char[] getString(int class_id, int object_id, int property_id){
		return Storage.getString(class_id, object_id, property_id);
	}


}

