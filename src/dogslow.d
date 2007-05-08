/*

Copyright (c) 2007 Bane <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

/**
*/
module dogslow;

private import std.stdio;

private import dnet;


private char[][][char[]] Classess;
private InternetAddress[uint] Clients;
private bool IsServer = false;
private bool IsConnected = false; // client only
private uint ClientId; // client only
private enum PacketType : ubyte {
	CLIENT_ID
}

///
class DogObject {
///
	this(){
	}
///
	~this(){
	}

///
	char[] getClassName() {
		return "";
	}
///
	uint getObjectId() {
		return 0;
	}

///
	void setString(char[] property_name, char[] value, bool replicate=true){
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
		return "";
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

/// Registers class with its properties.
public void registerClass(char[] class_name, char[][] class_properties){
	if (classRegistred(class_name))
		writefln("Class %s is allready registred", class_name);
	else
		Classess[class_name] = class_properties;
}

/// Get names of registred classess.
public char[][] getClassess(){
	return Classess.keys;
}

/// Get properties of class.
public char[][] getProperties(char[] class_name){
	return classRegistred(class_name) ? Classess[class_name] : cast(char[][])[];
}

/// Returns if class is allready registred.
public bool classRegistred(char[] class_name){
	return (class_name in Classess) != null;
}

///
DogObject addObject(char[] class_name){
	return null;
}

///
DogObject[] getObjects(char[] class_name){
	DogObject[] a;
	return a;
}

///
DogObject getObject(char[] class_name, uint object_id){
	return null;
}

///
void deleteObject(char[] class_name, uint object_id){
}

///
void deleteObject(DogObject dog_object){
}


/// on connect handler
private bool on_connect(InternetAddress address){
	if (IsServer){
		for (uint i = 0; i < 16; i++){
			if ((i in Clients) == null){
				// accept client connection and send client id
				Clients[i] = address;
				dnet_server_send([PacketType.CLIENT_ID] ~ [i], address);
				return true;
			}
		}
		return false;
	}
	else
		return true;
}


private void on_disconnect(InternetAddress address){
}

private void on_receive(ubyte[] data, InternetAddress address){
	if (IsServer){
	}
	else {
		switch(data[0]){
			case PacketType.CLIENT_ID:
				ClientId = cast(uint)data[1];
				IsConnected = true;
				break;
			default:
				break;
		}
	}
}



///
public bool init(){
	registerClass("client", ["address", "port"]);
	dnet_init(&on_connect, &on_disconnect, &on_receive);
	return true;
}

///
public void shutdown(){
	dnet_shutdown();
}

///
public bool clientConnect(char[] address, ushort port){
	IsServer = false;
	return dnet_client_connect(address, port);
}

///
public bool clientIsConnected(){
	return IsConnected;
}

///
public uint clientGetId(){
	return ClientId;
}

///
public bool serverCreate(char[] address, ushort port){
	IsServer = true;
	return dnet_server_create(address, port);
}

///
public uint[] serverGetClients(){
	return Clients.keys;
}

///
public void serverDisconnect(uint client_id){
	InternetAddress a = Clients[client_id];
	if (a != null)
		dnet_server_disconnect(a);
}

