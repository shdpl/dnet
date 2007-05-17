private import std.stdio;
private import std.string;

version(Windows)
	pragma(lib, "ws2_32.lib");

/**
 Auto resizeable FIFO container that stores char[] type.
 Overflow shouldn't happen becouse capacity will grow. 
 Underflow is handled by returning empty string.
 Capacity can only grow and unused data is overwritten, not cleaned up.
*/
public class FifoQueue {
	private uint Capacity;
	private char[][] Buff;
	private uint First;
	private uint Last;
	private uint Length;

	this(){
		First = 0;
		Last = 0;
		Capacity = 16; // start with default capacity
		Length = 0;
		Buff.length = Capacity;
	}

	public void put(char[] data){
		if (Length == Capacity){
			Capacity *= 2;
			Buff.length = Capacity;
		}

		Buff[Last] = data;
		Length++;

		if (Last == Capacity - 1)
			Last = 0;		
		else
			Last++;
	}
	public char[] get(){
		char[] s = ""; // we handle underflows by returning empty string
		if (Length > 0){
			Length--;
			s = Buff[First];
			if (First == Capacity - 1)
                        	First = 0;
	                else
        	                First++;

		}
		return s;
	}
	public uint length(){
		return Length;
	}

	public uint capacity(){
		return Capacity;
	}

	public char[] toString(){
		return format("<FifoQueue - capacity %d length %d first %d last %d>", Capacity, Length, First, Last);
	}

	unittest {
		FifoQueue q = new FifoQueue();
		assert(q.get() == "");
		assert(q.length == 0);
		q.put("a");
		q.put("b");
		q.put("c");
		assert(q.length == 3);
		assert(q.get() == "a");
		assert(q.length == 2);
		assert(q.get() == "b");
		assert(q.get() == "c");
		assert(q.get() == "");
		assert(q.length == 0);
		for(int i=0; i < 1024; i++){
			q.put("a");
                        assert(q.get() == "a");
                }
		writefln("FifoQueue unitest PASS");
	}

}




const char UNRELIABLE = 255;
const char GOTO = 254;
const char FINISHED = 253;

/*
 A tunnel to other virtual side.
 Tunnel takes care of packets to send and their order.

 This class is not sockets or thread related. It doesn't binds, sends or receives any network data.
 It stores and tracks what data is in and next out.
*/
class PeerQueue {
	FifoQueue Received; // incoming
	FifoQueue Reliable; // outgoing
	FifoQueue Unreliable; // outgoing

	char RecvId = 0;
	char SendId = 0;
	char[][250] SendBuff;

	/**
	*/
	this(){
		Received = new FifoQueue();
		Reliable = new FifoQueue();
		Unreliable = new FifoQueue();
	}

	/**
	 Sends data to other end. 
	*/
	void put(char[] data, bool reliable){
		if (reliable)
			Reliable.put(data);
		else
			Unreliable.put([UNRELIABLE] ~data);
	}

	/**
         Reads data received from other end. 
         When there are no more left empty string is returned.
        */
	char[] get(){
		return Received.get();
	}

	/**
	 Feeds incoming UDP packet addressed to this end of peer.
	*/
	void packetPut(char[] data){

		switch (data[0]) {
			case UNRELIABLE: // unreliable packet received
				Received.put(data[1..length].dup);
				break;

			case FINISHED: // other side got all 250 packets in a batch, reset send buffer and start from packet id 0
				for (int i=0; i < SendBuff.length; i++)
					SendBuff[i] = "";
				SendId = 0;
				break;

			case GOTO: // other side tells us to restart transmission from this packet id becouse some packets got lost
				SendId = data[1];
				break;

			default: // here we handle regular packets
				char next_packet_id = RecvId == 249 ? 0 : RecvId + 1;
				char last_packet_id = RecvId == 0 ? 249 : RecvId - 1;

				if (data[0] == RecvId){
					Received.put(data[1..length].dup);
					if (RecvId == 249)
						Unreliable.put(cast(char[])([FINISHED] ~ []));
                        	        RecvId = next_packet_id;
				}
				else if (data[0] == last_packet_id){
					// allready got this packet, ignore it
				}
				else {
					// by here now, we must have got unordered packet 
					// So we must notify other side which packet are we expecting
					Unreliable.put(cast(char[])([GOTO] ~ [RecvId]));
				}

		}				
	}

	/**
	 Returns raw data for next packet to transmit to other side.
	 If there are no packets waiting then empty string.
	*/
	public char[] packetGet(){
		// now sending procedures
		// procedure is - packets are sent from id's 0 - 249
		// packet 249 is repeatedly sent untill there is GOT_ALL from other end
		// with id = 0
		// that means other side got all 250 packets so we can reset SendBuff

		// first we store data we want to send in SendBuff if it is not present
		if (SendId < 250 && SendBuff[SendId].length == 0){
			if (Reliable.length > 0)
				SendBuff[SendId] = Reliable.get();
		}

		char[] s = "";
		if (Unreliable.length > 0) // send unreliable data
			s = Unreliable.get();
		else if (SendBuff[SendId].length > 0 && SendId <= 249) {// if there is reliable data for sending, send it
			s = cast(char[])([SendId] ~ SendBuff[SendId]); // note for ++
			if (SendId < 249)
				SendId++;
		}
		return s;

	}

	/**
	 Use for quick debug description of object.
	*/
	public char[] toString(){
		return format("<PeerQueue - RecvId %d SendId %d Received %d Reliable %d Unreliable %d>", 
			RecvId, SendId, Received.length, Reliable.length, Unreliable.length
		);
	}

	unittest {

		// new empty queue, no data to read or send or anything
		PeerQueue q = new PeerQueue();
		assert(q.get() == "");
		assert(q.packetGet() == "");

		// unreliable sending
		q.put("abc", false);
		q.put("def", false);
		assert(q.packetGet() == [UNRELIABLE] ~"abc");
		assert(q.packetGet() == [UNRELIABLE] ~"def");
		assert(q.packetGet() == "");

		// reliable sending
		q.put("efg", true);
		q.put("ddd", true);
		assert(q.packetGet() == "\x00efg");
		assert(q.packetGet() == "\x01ddd");
		q.put("eee", true);
		assert(q.packetGet() == "\x02eee");
		assert(q.packetGet() == "");

		// test does SendId increments only to 249 then goes back to 0
		for (int i=3; i<250; i++){
			q.put(format("x%d", i), true);
			assert(q.packetGet() == cast(char[])[i] ~ format("x%d", i));
		}
		assert(q.packetGet() == cast(char[])[249] ~ format("x%d", 249));
		assert(q.packetGet() == cast(char[])[249] ~ format("x%d", 249));

		// test if packet id 249 will be transmitted repetaedly utill there is reply with FINISHED
		q.put("efg", true);
		q.put("xcf", true);
		assert(q.packetGet() == cast(char[])[249] ~ format("x%d", 249));
		q.packetPut(cast(char[])[FINISHED]);
		assert(q.packetGet() == "\x00efg");
		assert(q.packetGet() == "\x01xcf");

		// simulate other side didnt get some packets and now is asking to retransmit
		q.packetPut(cast(char[])[GOTO, 0] );
		assert(q.packetGet() == "\x00efg");
		assert(q.packetGet() == "\x01xcf");

		// simulate we get packets in order
		assert(q.packetGet() == "");
		q.packetPut("\x00a" );
		q.packetPut("\x01b" );
		q.packetPut("\x02c" );
		assert(q.get() == "a");
		assert(q.get() == "b");
		assert(q.get() == "c");
		assert(q.get() == "");
		assert(q.packetGet() == "");

		// simulate we didn get packet id 4. we expect to send back 2 GOTO packets, one for each of 2 we got affter missing one
		q.packetPut("\x03d" );
		q.packetPut("\x05e" );
		q.packetPut("\x06f" );
		assert(q.packetGet() == cast(char[])[GOTO, 4]);
		assert(q.packetGet() == cast(char[])[GOTO, 4]);
		assert(q.packetGet() == "");

		writefln("PeerQueue unitest PASS");
	}

}

import std.c.time;

import std.thread;
import std.socket;
version(Windows) 
	pragma(lib, "ws2_32.lib");


/**
TODO - detecting disconnect. also, when client disconnects his peer must be removed.
*/
class DnetServer {

	UdpSocket Socket;
	bool IsAlive;
	PeerQueue[char[]] ClientsPeer;
	Address[char[]] ClientsAddress;
	Thread Listener;
	Thread Watcher;

	this(ushort port){
		Socket = new UdpSocket(AddressFamily.INET);
		Socket.bind(new InternetAddress(3333));
		IsAlive = true;
		assert(Socket != null);
		assert(Socket.isAlive());
		Listener = new Thread(&listener);
		Listener.start();
		Watcher = new Thread(&watcher);
		Watcher.start();
	}

	int listener(){
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

	int watcher(){
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
					writefln("server sends raw %s", cast(ubyte[])buff);
					Socket.sendTo(buff, ClientsAddress[client]);
					buff = peer.packetGet();
				}
			}
			usleep(1000);
		}
		return 0;
	}

	bool onConnect(Address client){
		writefln("Connected from %s", client.toString());
		return true;
	}

	void onDisconnect(Address client){
		writefln("Disconnected from %s", client.toString());
	}

	void onReceive(Address client, char[] data){
		writefln("Packet from %s, data %s", client.toString(), data);
	}

	bool listening(){
		return true;
	}

	Address[] clients(){
		return ClientsAddress.values;
	}

	void send(Address client, char[] data, bool reliable){
		if ((client.toString() in ClientsAddress) != null)
			ClientsPeer[client.toString()].put(data, reliable);
	}

	void broadcast(char[] data, bool reliable){
		writefln("broadcast");
		foreach(char[] client, PeerQueue peer; ClientsPeer){
			writefln("broadcast to %s data %s", client, data);
			peer.put(data, reliable);
		}
	}

}


public class DnetClient {

	UdpSocket Socket;
	Address Host;
	PeerQueue Peer;
	bool IsConnected;
	bool IsAlive;
	Thread Listener;
	Thread Watcher;


	this(char[] address, ushort port){
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
	}

	int listener(){
		writefln("listener thread initialized");
                Address address;
                int size;
                char[1024] buff;
                while (IsAlive){
                        size = Socket.receiveFrom(buff, address);
			// receive packets only coming from server host and store them in peer
			// if it is first packet received from server then call onConnect
                        if (size > 0 && address.toString() == Host.toString()){
				writefln("client get packet %s", cast(ubyte[])buff[0..size]);
                                if (IsConnected == false){
					IsConnected = true;
                                        onConnect();
				}
                                Peer.packetPut(buff[0..size]);
                        }
                }
                return 0;
	}

	int watcher(){
		writefln("watcher thread initialized");
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


	void onConnect(){
		writefln("on connect");
	}

	void onDisconnect(){
		writefln("on disconnect");
	}

	void onReceive(char[] data){
		writefln("on receive data %s", data);
	}

	bool connected(){
		return IsConnected;
	}

	void send(char[] data, bool reliable){
		//writefln("send");
		Peer.put(data, reliable);
	}
}

