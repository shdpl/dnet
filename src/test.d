private import std.stdio;
private import std.socket;

version(Windows)
	pragma(lib, "ws2_32.lib");

/**
 Auto resizeable FIFO queue that holds char[]
 Overflow shouldn't happen becouse capacity will grow. 
 Underflow is handled by returning empty string.
 Capacity will not shrink or data cleanedup ever ever :)
*/
class FifoQueue {
	uint Capacity;
	char[][] Buff;
	uint First;
	uint Last;
	uint Length;

	this(){
		First = 0;
		Last = 0;
		Capacity = 16; // start with default capacity
		Length = 0;
		Buff.length = Capacity;
	}

	void put(char[] data){
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
	char[] get(){
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
	uint length(){
		return Length;
	}

	uint capacity(){
		return Capacity;
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
const char STATUS_REQUEST = 254;
const char STATUS_REPORT = 253;
const char GOT_ALL = 252;

/*
 A tunnel to other side defined by address.
 All packets send there are guaranteeded to get there and in order if set so.
 It is not job for this class to know is otherside alive or not.
 And as it is UDP protocol, it don't know anything about connecting/disconnecting 
 and will hang forever waiting for reply if other end is down.

 This class is not thread related. 
 It is required to call sync method in a loop for it to be able to send & receive data.
*/
class PeerTunnel {
	Address RemoteHost;
	UdpSocket Socket;
	FifoQueue Received;
	FifoQueue Pending;

	char RecvId = 0;
	char SendId = 0;
	char[][250] SendBuff;

	/**
	 Initializes class and points it to other end.
	*/
	this(ushort listen_port, char[] remote_host, ushort remote_port){
		RemoteHost = new InternetAddress(remote_host, remote_port);
	        Socket = new UdpSocket(AddressFamily.INET);
		Socket.bind(new InternetAddress(listen_port));
		Socket.blocking(true);

		Received = new FifoQueue();
		Pending = new FifoQueue();
	}

	/**
	 Sends data to other end. 
         All reliable packets are guaranteded to get in order 
         and on target if other end is alive.
	 All unreliable packets are sent immediatelly, 
         while reliable are stored in queue and sent on next sync() call.
	*/
	void send(char[] data, bool reliable){
		if (reliable)
			Pending.put(data);
		else
			Socket.sendTo(data, RemoteHost);
	}

	/**
         Reads cached data received from other end. 
         Repeat this function to get all stored packets.
         When there are no more left empty string is returned.
        */
	char[] receive(){
		return Received.get();
	}

	/**
	 Sends all packets waiting in pending queue and receives incomming packets.
	*/
	void sync(){
		// first, receive procedure
		char[1024] buff;
		int size;
		while (true){
			size = Socket.receiveFrom(buff, RemoteHost);
			if (size <= 0)
				break;

			writefln(cast(ubyte[])buff[0..size]);

			switch (buff[0]) {
				case UNRELIABLE: // unreliable packet received
					Received.put(buff[1..size].dup);
					break;

				case STATUS_REQUEST: // status request, we send back last send id
					Socket.sendTo(cast(void[])([STATUS_REPORT] ~ [SendId]), SocketFlags.NONE, RemoteHost);
					break;
				case GOT_ALL: // other side got all 250 packets in a batch, reset send buffer
					for (int i=0; i < SendBuff.length; i++)
						SendBuff[i] = "";
					SendId = 0;
                                        break;

				case STATUS_REPORT: // other side tells us wich packet is expecting next
					SendId = buff[1];
					break;

				default: // here we handle regular packets
					char next_packet_id = RecvId == 249 ? 0 : RecvId + 1;
					if (buff[0] == next_packet_id){
						Received.put(buff[1..size].dup);

						if (RecvId == 249)
							Socket.sendTo(cast(void[])([GOT_ALL] ~ []), SocketFlags.NONE, RemoteHost);


	                        	        RecvId = next_packet_id;
					}
					else if (buff[0] == RecvId){
						// allready got this packet, ignore it
					}
					else {
						// by here now, we must have got unordered packet 
						// So we must notify other side which packet are we expecting
						Socket.sendTo(cast(void[])([STATUS_REPORT] ~ [next_packet_id]), SocketFlags.NONE, RemoteHost);

					}

			}				
		}

		// now sending procedures
		// procedure is - packets are sent from id's 0 - 249
		// packet 249 is repeatedly sent untill there is GOT_ALL from other end
		// with id = 0
		// that means other side got all 250 packets so we can reset SendBuff

		// first we store data we want to send in SendBuff if it is not present
		if (SendId < 250 && SendBuff[SendId].length == 0){
			char[] tmp = Pending.get();
			if (tmp.length > 0)
				SendBuff[SendId] = tmp;
		}

		// if there is data for sending, send it
		if (SendBuff[SendId].length > 0)
			Socket.sendTo(cast(void[])([SendId] ~ SendBuff[SendId]), SocketFlags.NONE, RemoteHost);

	}
}

import std.c.time;

int main(){
	PeerTunnel t = new PeerTunnel(3333, "localhost", 3333);
	char[] buff;
	while(1){
		t.send("bane", false);
		do {
			buff = t.receive();
			if (buff.length > 0)
				writefln("got %s", buff);
		} while (buff.length > 0);
		t.sync();
		usleep(1000*10);
	}

	return 0;
}

/*
char[][uint][]

1int peer_listening_func(void* unused){
	// getpacket
	if packet_id == UNRELIABLE
		call_receive func, packet is unreliable
	else if packt_id = expected packet id
		inc counter, display packet
	else if packet_id <> expected packet id
		ignore packet & send back GOTO packet 

	else if packet_id == GOTO packet
		ignore packet & move counter on that peer on requested packet id

	else if packet_id == STATUS
		ignore & send back STATUS with id of last packet received
	
		

	return 0;
}



void dnet_peer_send(InternetAddress, bool reliable, char[] data){
	if (reliable)
		// append to buffer
	else
		// send immediatly, packet_id = UNRELIABLE
}



/*
unreliable are sent immediatelly

Sending buffer (must keep much more than 255 packets for send)
char[][uint][address]

last_recv (0-254) - packets with id 255 are unreliable and will allways be accepted
char[address]

STATUS - "hey, send me back id of last packet you got from me"
STATUS char - "hey, this is id of last packet I got from you"
GOTO char - "yo man, I need you to send me packets starting with this id (I didn't get them or whatever)"

tunnel.send(address, mode, data)
tunnel.get(address, mode, data)
tunnel.listener(); // thread
tunnel.sender(); // thread

tunnel_got
*/
