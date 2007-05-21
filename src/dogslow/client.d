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
private import std.string;
private import std.c.time;
private import std.c.stdlib;

private import dnet.client;
private import dogslow.storage;

const int CLIENTID = 0;
const int REPLICATE = 1;
const int UPLOADED = 2;
const int DELETE = 3;

// predefined object
const int CLIENT = 0;
// predefined property
const int ADDRESS = 0;


public class DogslowClient : DnetClient {


	private {
		bool Uploaded = false;
		int ClientId = -1;
                DogslowStorage Storage;
        }


        this(){
                super();
                Storage = new DogslowStorage();
        }


	public bool connect(char[] address, ushort port){
		writefln("connecting, geting id & uploading data from server...");
		bool b = super.connect(address, port);
		// wait untill all data from server is uploaded
		if (b){
			while(IsAlive){
				if (Uploaded && ClientId > -1){
					writefln("data uploaded");
					return true;
				}
				msleep(50);
			}
		}
		return false;
	}

	public int getClientId(){
		return ClientId;
	}

	public void onConnect(){
	}

	public void onReceive(char[] data){
		writefln("got > %s", cast(ubyte[])data);
		switch (data[0]){
			case CLIENTID:
				ClientId = data[1];
				srand(ClientId);
				break;
			case REPLICATE:
				int class_id = data[1];
				int object_id = data[2]*256+data[3];
				int property_id = data[4];
				Storage.setRaw(class_id, object_id, property_id, data.ptr + 5, data.length - 5);
				break;
			case UPLOADED:
				Uploaded = true;
				break;
			case DELETE:
				int class_id = data[1];
				int object_id = data[2]*256 + data[3];
				Storage.del(class_id, object_id);
				break;
			default:
		}
	}

	public void onDisconnect(){
		ClientId = -1;
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
		send(buff, true);
	}

	public void setString(int class_id, int object_id, int property_id, char[] value, bool replicate){
		if (replicate){
			char[] buff;
			buff = cast(char[])[REPLICATE, class_id, object_id/256, object_id%256, property_id] ~ value;
			send(buff, true);
		}
		else
			Storage.setString(class_id, object_id, property_id, value);
	}

	public char[] getString(int class_id, int object_id, int property_id){
		return Storage.getString(class_id, object_id, property_id);
	}


}

