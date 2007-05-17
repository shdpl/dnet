module dnet.client;

import std.stdio;
import std.string;
import std.c.time;
import std.thread;
import std.socket;
import dnet.peer_queue;

version(Windows) 
	pragma(lib, "ws2_32.lib");

public class DnetClient {

	private {
		UdpSocket Socket;
		Address Host;
		PeerQueue Peer;
		bool IsConnected;
		bool IsAlive;
		Thread Listener;
		Thread Watcher;
	}

	public bool connect(char[] address, ushort port){
		Peer = new PeerQueue();
		Socket = new UdpSocket(AddressFamily.INET);
		Host = new InternetAddress(address, port);
		IsConnected = false;
		IsAlive = true;
		assert(Socket != null);
		assert(Socket.isAlive());
		Listener = new Thread(&listener);
		Listener.start();
		Watcher = new Thread(&watcher);
		Watcher.start();
		return true;
	}

	private int listener(){
		//writefln("listener thread initialized");
		//long last_recv = getUTCtime();
                Address address;
                int size;
                char[1024] buff;
                while (IsAlive){
                        size = Socket.receiveFrom(buff, address);
			// receive packets only coming from server host and store them in peer
			// if it is first packet received from server then call onConnect
                        if (size > 0 && address.toString() == Host.toString()){
				// trying to implement disconnect event 
				//if ((getUTCtime() - last_recv)/TicksPerSecond > 1)
				//	Peer.put(cast(char[])[IGNORE], false);
				//last_recv = getUTCtime();

				//writefln("client get packet %s", cast(ubyte[])buff[0..size]);
                                if (IsConnected == false){
					IsConnected = true;
                                        onConnect();
				}
                                Peer.packetPut(buff[0..size]);
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
				buff = Peer.packetGet();
			}
			usleep(1000);
		}
		return 0;
	}


	public void onConnect(){
		writefln("on connect");
	}

	public void onDisconnect(){
		writefln("on disconnect");
	}

	public void onReceive(char[] data){
		writefln("on receive data %s", data);
	}

	public bool connected(){
		return IsConnected;
	}

	public void send(char[] data, bool reliable){
		//writefln("send");
		Peer.put(data, reliable);
	}
}

