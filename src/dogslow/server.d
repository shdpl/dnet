/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

/**
*/
module dogslow.server;


/**
*/
public class DogslowServer : DogslowHost {
}



private import std.stdio;
private import std.string;
private import std.c.time;
private import std.random;

private import dnet;


private char[][][char[]] Classess;
private ubyte[][char[]][uint][char[]] Cache; 
// cache of all properties, it goes like Cache[class_name][object_id][property_name]
private InternetAddress[uint] Clients;
private bool IsServer = false;
private bool IsConnected = false; // client only
private uint ClientId; // client only
private bool Updated = false; // client only
private enum PacketType : ubyte {
	CLIENT_ID,
	REG_CLASS,
	UPDATED, 
	REG_OBJECT,
	SET_PROP
}

///
class DogObject {
	private char[] className;
	private uint objectId;


///
	this(char[] class_name, uint object_id){
		className = class_name;
		objectId = object_id;
	}
///
	~this(){
	}

///
	char[] getClassName() {
		return className;
	}
///
	uint getId() {
		return objectId;
	}

///
	void setString(char[] property_name, char[] value, bool replicate=true){
		if (IsServer){
                        Cache[className][objectId][property_name] = cast(ubyte[])value;

			serverBroadcast([cast(ubyte)PacketType.SET_PROP, cast(ubyte)objectId] ~ cast(ubyte[])(format("%s %s ", className, property_name)) ~ cast(ubyte[])value);

		}
		else {
			dnet_client_send([cast(ubyte)PacketType.SET_PROP, cast(ubyte)objectId] ~ cast(ubyte[])(format("%s %s ", className, property_name)) ~ cast(ubyte[])value);
		}
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

/// Registers class with its properties. Initial registration is done at server first.
public void registerClass(char[] class_name, char[][] class_properties){
	if (IsServer){
		Classess[class_name] = class_properties;
		serverBroadcast(regClassPacket(class_name, class_properties));
	}
	else
		dnet_client_send(regClassPacket(class_name, class_properties));
}


private ubyte[] regClassPacket(char[] class_name, char[][] class_properties){
	return cast(ubyte[])[PacketType.REG_CLASS]  ~ cast(ubyte[])class_name ~ cast(ubyte[])" "  ~ cast(ubyte[])join(class_properties, " ");
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
	//uint object_id = rand();
	//while(true){
	//	if ((object_id in Cache[class_name]) == null)
	//		break;
	//	else
	//		object_id = rand();
	//}
	return new DogObject(class_name, cast(ubyte)(rand()/256));
}

///
DogObject[] getObjects(char[] class_name){
	DogObject[] tmp;
	if ((class_name in Cache) != null){
		tmp.length = Cache[class_name].length;
		int i = 0;
		foreach(uint object_id; Cache[class_name].keys){
			tmp[i] = new DogObject(class_name, object_id);
			i++;
		}
	}
	return tmp;
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
				writefln("client connected from " ~ address.toString());
				// accept client connection and send client id to him
				Clients[i] = address;
				dnet_server_send([PacketType.CLIENT_ID] ~ [i], address);

				// register a special class to hold client data
				Classess["clients"] = ["address", "port"];

				// send a newcomer all data
				foreach(char[] class_name, char[][] class_properties; Classess){
					dnet_server_send(regClassPacket(class_name, class_properties), address);
					if ((class_name in Cache) != null && Cache[class_name].length > 0){
						foreach(uint object_id; Cache[class_name].keys){
							if (Cache[class_name][object_id].length > 0){
								foreach(char[] property_name, ubyte[] data; Cache[class_name][object_id]){
									writefln("sending data for class %s with id %d for property %s with value %s", class_name, object_id, property_name, data);
									dnet_server_send([cast(ubyte)PacketType.SET_PROP, cast(ubyte)object_id] ~ cast(ubyte[])(format("%s %s ", class_name, property_name)) ~ data, address);
								}
							}
						}
					}
				}

				// tell client all data is here, he can continue
				dnet_server_send([PacketType.UPDATED], address);

				
				return true;
			}
		}
		return false;
	}
	else {
		return true;
	}
}


///
private void on_disconnect(InternetAddress address){
	if (IsServer){
	}
	else {
	}
}

/// sends to all connected clients
private void serverBroadcast(ubyte[] data){
	foreach(uint client_id, InternetAddress address; Clients)
		dnet_server_send(data, address);
}

private void on_receive(ubyte[] data, InternetAddress address){
	switch(data[0]){
		case PacketType.CLIENT_ID:
			if (!IsServer){
				ClientId = cast(uint)data[1];
				IsConnected = true;
				writefln("connected to server");
			}
			break;
		case PacketType.REG_CLASS:
			char[][] buff = split(cast(char[])data[1..length]);
			Classess[cast(char[])buff[0]] = cast(char[][])buff[1..length];
			if (IsServer)
				serverBroadcast(regClassPacket(cast(char[])buff[0], cast(char[][])buff[1..length]));
			break;
		case PacketType.UPDATED:
			if (!IsServer)
				Updated = true;
			break;
		case PacketType.SET_PROP:
			// packet is [packet_type][object_id][space][class_name][space][prop_name][space][value]
			// I know it is not efficient, but it will be optimized

			uint object_id = cast(uint)data[1];
			char[][] buff = split(cast(char[])data[2..length], " ");
			char[] class_name = buff[0];
			char[] property_name = buff[1];

			writefln("got packet SET_PROP for class %s with id %d for property %s", class_name, object_id, property_name);			
			Cache[class_name][object_id][property_name] = cast(ubyte[])join(buff[2..length], " ");
			if (IsServer)
				serverBroadcast(data);
			break;
		default:
			break;
	}
}



///
public bool init(){
	IsConnected = false;
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
	IsConnected = false;
	Updated = false;
	// client program execution must be stoped untill all data is downloaded
	if (dnet_client_connect(address, port)){
		writefln("Connecting...");
		while(!IsConnected){usleep(10000);}
		writefln("Downloading...");
		while(!Updated){usleep(10000);}
		writefln("Connected");
		return true;
	}
	return false;
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
	if (Clients[client_id] != null){
		dnet_server_disconnect(Clients[client_id]);
		Clients.remove(client_id);
	}
}

