module dnet.server;

import std.stdio;
import std.string;
import std.c.time;
import std.thread;
public import std.socket; // need Address defined
import dnet.peer_queue;

version(Windows) 
	pragma(lib, "ws2_32.lib");


/**
TODO - detecting disconnect. also, when client disconnects his peer must be removed.
*/
public class DnetServer {

	private {
		UdpSocket Socket;
		bool IsAlive;
		PeerQueue[char[]] ClientsPeer;
		Address[char[]] ClientsAddress;
		Thread Listener;
		Thread Watcher;
	}

	public bool create(ushort port){
		Socket = new UdpSocket(AddressFamily.INET);
		Socket.bind(new InternetAddress(3333));
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
		Address address;
		int size;
		char[1024] buff;
		while (IsAlive){
			// store incoming packets into peer
			size = Socket.receiveFrom(buff, address);
			if (size > 0){
				if ((address.toString() in ClientsPeer) == null){
					if (onConnect(address)){
						ClientsPeer[address.toString()] = new PeerQueue();
						ClientsAddress[address.toString()] = address;
					}
				}
				if ((address.toString() in ClientsPeer) != null)
					ClientsPeer[address.toString()].packetPut(buff[0..size]);
			}
		}
		return 0;
	}

	private int watcher(){
		char[] buff;
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
					buff = peer.packetGet();
				}
			}
			usleep(1000);
		}
		return 0;
	}

	public bool onConnect(Address client){
		writefln("Connected from %s", client.toString());
		return true;
	}

	public void onDisconnect(Address client){
		writefln("Disconnected from %s", client.toString());
	}

	public void onReceive(Address client, char[] data){
		writefln("Packet from %s, data %s", client.toString(), data);
	}

	public bool listening(){
		return true;
	}

	public Address[] clients(){
		return ClientsAddress.values;
	}

	public void send(Address client, char[] data, bool reliable){
		if ((client.toString() in ClientsAddress) != null)
			ClientsPeer[client.toString()].put(data, reliable);
	}

	public void broadcast(char[] data, bool reliable){
		//writefln("broadcast");
		foreach(char[] client, PeerQueue peer; ClientsPeer){
			//writefln("broadcast to %s data %s", client, data);
			peer.put(data, reliable);
		}
	}

}
