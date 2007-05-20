/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

/**
Comment:
Address type is same as std.socket.Address.
*/

module dnet.server;

import std.stdio;
import std.string;
import std.c.time;
import std.thread;
public import std.socket; // need Address defined
import std.date;
import dnet.peer_queue;

version(Windows) 
	pragma(lib, "ws2_32.lib");


/**
Server that handles multiple clients.
Inherit this class with yours and override onConnect, onReceive and onDisconnect methods, 
then call create method.
*/
public class DnetServer {

	private {
		UdpSocket Socket;
		bool IsAlive;
		PeerQueue[char[]] ClientsPeer;
		Address[char[]] ClientsAddress;
		Thread Listener;
		Thread Watcher;

		long[char[]] LastSend;
		long[char[]] LastRecv;
	}


	this(){
	}


	~this(){
		IsAlive = false;
		Listener.wait(1000);
		Watcher.wait(1000);
	}


	/**
	Creates server listening on local address with selected port.
	Return:
	true if creating suceeded.
	*/
	public bool create(ushort port){
		bool is_created = true;
		IsAlive = false;
		Socket = new UdpSocket(AddressFamily.INET);
		try {
			Socket.bind(new InternetAddress(3333));
		}
		catch (Exception e){
			is_created = false;
		}
		assert(Socket != null);
		assert(Socket.isAlive());
		Listener = new Thread(&listener);
		Listener.start();
		Watcher = new Thread(&watcher);
		Watcher.start();
		IsAlive = Socket.isAlive();
		return is_created;
	}


	private int listener(){
		Address address;
		int size;
		char[1024] buff;
		char[] client;
		while (IsAlive){
			// store incoming packets into peer
			size = Socket.receiveFrom(buff, address);
			if (size > 0){
				client = address.toString();
				if ((address.toString() in ClientsPeer) == null){
					if (onConnect(address)){
						ClientsPeer[client] = new PeerQueue();
						ClientsAddress[client] = address;
						LastSend[client] = getUTCtime();
						LastRecv[client] = getUTCtime();
					}
				}
				if ((client in ClientsPeer) != null){
					ClientsPeer[client].packetPut(buff[0..size]);
					LastRecv[client] = getUTCtime();
				}
			}
		}
		return 0;
	}


	private int watcher(){
		char[] buff;
		char[] remove;
		while (IsAlive){
			foreach(char[] client, PeerQueue peer; ClientsPeer){
				// forward stored incoming packets to onReceive handler
				buff = peer.get();
				while (buff.length > 0){
					onReceive(ClientsAddress[client], buff);
					buff = peer.get();
				}
				// send raw packets stored for sending
				buff = peer.packetGet();
				while (buff.length > 0){
					//writefln("server sends raw %s", cast(ubyte[])buff);
					Socket.sendTo(buff, ClientsAddress[client]);
					LastSend[client] = getUTCtime();
					buff = peer.packetGet();
				}

				// timeout / disconnect handling
				// send empty packet on each second of idle connetion (packets must be flowing!)
				if ((getUTCtime() - LastSend[client])/TicksPerSecond > 1.00){
					buff = [IGNORE];
					Socket.sendTo(buff, ClientsAddress[client]);
				}
				// if there is more than 3 seconds of no packet from remote end, we act like we lost connection
				if ((getUTCtime() - LastRecv[client])/TicksPerSecond > 3.00){
					onDisconnect(ClientsAddress[client]);
					ClientsAddress.remove(client);
					ClientsPeer.remove(client);
					LastSend.remove(client);
					LastRecv.remove(client);
				}
			}

			msleep(10);
		}
		return 0;
	}


	/**
	Method called on first packet received from client. 
	Override it if you want to handle this event.

	Return:
	true if client will be accepted, false to reject connection attempt.
	*/
	public bool onConnect(Address client){
		writefln("Connected from %s", client.toString());
		return true;
	}


	/**
	Method called on client timeout. Override it if you want to handle this event.
	*/
	public void onDisconnect(Address client){
		writefln("Disconnected from %s", client.toString());
	}


	/**
	Method called on data packet received from client. Override it if you want to handle this event.
	*/
	public void onReceive(Address client, char[] data){
		writefln("Packet from %s, data %s", client.toString(), data);
	}


	/**
	Return:
	List of all connected clients.
	*/
	public Address[] clients(){
		return ClientsAddress.values;
	}


	/**
	Sends data packet to client with optional reliability.
	*/
	public void send(Address client, char[] data, bool reliable){
		if (data.length > 0 && (client.toString() in ClientsAddress) != null)
			ClientsPeer[client.toString()].put(data, reliable);
	}


	/**
	Sends data packet to all connected clients with optional reliability.
	*/
	public void broadcast(char[] data, bool reliable){
		if (data.length > 0){
			foreach(char[] client, PeerQueue peer; ClientsPeer){
				peer.put(data, reliable);
			}
		}
	}


	unittest {
	}

}
