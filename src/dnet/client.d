/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/


/**
*/
module dnet.client;

import std.stdio;
import std.string;
import std.c.time;
import std.thread;
import std.socket;
import std.date;
import dnet.peer_queue;

version(Windows) 
	pragma(lib, "ws2_32.lib");

/**
Client that can connect to server.
Inherit this class with yours and override onConnect, onReceive and onDisconnect methods, 
then call connect method.
*/
public class DnetClient {

	private {
		UdpSocket Socket;
		Address Host;
		PeerQueue Peer;
		bool IsConnected;
		bool IsAlive;
		Thread Listener;
		Thread Watcher;
		long LastSend;
		long LastRecv;
	}


	this(){
	}


	~this(){
		IsAlive = false;
		Listener.wait(1000);
		Watcher.wait(1000);
	}


	/**
	Connects to server listening at address with port. 
	Return:
	true if connected suceeded.
	*/
	public bool connect(char[] address, ushort port){
		Peer = new PeerQueue();
		Socket = new UdpSocket(AddressFamily.INET);
		Host = new InternetAddress(address, port);
		IsConnected = false;
		IsAlive = Socket.isAlive();
		assert(Socket != null);
		assert(Socket.isAlive());

		LastSend = getUTCtime();
		LastRecv = getUTCtime();

		Listener = new Thread(&listener);
		Listener.start();
		Watcher = new Thread(&watcher);
		Watcher.start();

		// send first packet to see is there answer
		send("Let me in!", true);

		// wait for 3 seconds to see are we connected, if not return false
		for(int i = 0; i < 30; i++){
			if (IsConnected)
				return true;
			else
				msleep(100);
		}
		return IsConnected;
	}


	private int listener(){
                Address address;
                int size;
                char[1024] buff;
                while (IsAlive){
                        size = Socket.receiveFrom(buff, address);
			// receive packets only coming from server host and store them in peer
			// if it is first packet received from server then call onConnect
                        if (size > 0 && address.toString() == Host.toString()){
				//writefln("client get packet %s", cast(ubyte[])buff[0..size]);
                                if (IsConnected == false){
					IsConnected = true;
                                        onConnect();
				}
                                Peer.packetPut(buff[0..size]);
				LastRecv = getUTCtime();
                        }
                }
                return 0;
	}


	private int watcher(){
		//writefln("watcher thread initialized");
		char[] buff;
		while(IsAlive){
			// forward stored incoming packets to onReceive handler
			buff = Peer.get();
			while (buff.length > 0){
				onReceive(buff);
				buff = Peer.get();
			}
			// send raw packets stored for sending
			buff = Peer.packetGet();
			while (buff.length > 0){
				Socket.sendTo(buff, Host);
				LastSend = getUTCtime();
				buff = Peer.packetGet();
			}

			// timeout / disconnect handling
			// send empty packet on each second of idle connetion (packets must be flowing!)
			if ((getUTCtime() - LastSend)/TicksPerSecond > 1.00){
				buff = [IGNORE];
				Socket.sendTo(buff, Host);
			}
			// if there is more than 3 seconds of no packet from remote end, we act like we lost connection
			if ((getUTCtime() - LastRecv)/TicksPerSecond > 3.00){
				IsAlive = false;
				IsConnected = false;
				onDisconnect();
			}

			msleep(50);
		}
		return 0;
	}


	/**
	Method called on first packet received from server. Override it if you want to handle this event.
	*/
	public void onConnect(){
		writefln("on connect");
	}


	/**
	Method called on server timeout. Override it if you want to handle this event.
	*/
	public void onDisconnect(){
		writefln("on disconnect");
	}


	/**
	Method called on data packet received from server. Override it if you want to handle this event.
	*/
	public void onReceive(char[] data){
		writefln("on receive data %s", data);
	}


	/**
	Return:
	true if connected to server.
	*/
	public bool connected(){
		return IsConnected;
	}


	/**
	Sends data packet to server with optional reliability.
	*/
	public void send(char[] data, bool reliable){	
		if (data.length > 0)
			Peer.put(data, reliable);
	}


	unittest {
	}


}

