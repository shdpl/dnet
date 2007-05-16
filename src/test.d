private import std.stdio;
private import std.string;

version(Windows)
	pragma(lib, "ws2_32.lib");

/**
 Auto resizeable FIFO container that stores char[] type.
 Overflow shouldn't happen becouse capacity will grow. 
 Underflow is handled by returning empty string.
 Capacity will not shrink or data cleanedup ever ever :)
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

		PeerQueue q = new PeerQueue();
		// new empty queue, no data to read or send or anything
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

		// test if packet id 249 will be transmitted repetaedly utill there is reply with GOT_ALL
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

int main(){

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
