module dnet.peer_queue;

import std.stdio;
import std.string;
import dnet.fifo_queue;


const char UNRELIABLE = 255;
const char GOTO = 254;
const char FINISHED = 253;
const char IGNORE = 252;

/*
 A tunnel to other virtual side.
 Tunnel takes care of packets to send and their order.

 This class is not sockets or thread related. 
 It doesn't binds, sends or receives any network data.
 It stores and tracks what data is in and next out.

 Toward perfection: split larger data to chuns and send in separate packets?
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

			case IGNORE: // we do just that, ignore the packet
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
