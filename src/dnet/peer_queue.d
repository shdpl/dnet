/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/


module peer_queue;

import std.stdio;
import std.string;
import fifo_queue;


protected const char UNRELIABLE = 255;
protected const char GOTO = 254;
protected const char FINISHED = 253;
protected const char IGNORE = 252;

/**
 Utility used to translate data you want to send into raw UDP packets & decrypts received UDP packets to data you can read.
 It takes care of packet reliability and ordered sending.

 This class is not sockets or thread related. 
 It doesn't binds, sends or receives any network data.
 It only manipulates char arrays.

 TODO:
  split larger data to chunks and send in separate packets, limit packet size
*/
public class PeerQueue {
	FifoQueue Received; // incoming
	FifoQueue Reliable; // outgoing
	FifoQueue Unreliable; // outgoing

	char RecvId = 0;
	char SendId = 0;
	char[][250] SendBuff;

	this(){
		Received = new FifoQueue();
		Reliable = new FifoQueue();
		Unreliable = new FifoQueue();
	}

	/**
	 Writes data packet you want to send to other end. 
	Packet can be reliable if you want, meaning it will get there and in same order you send it.
	If not, it might get on destination, might not, or in unknown order.
	*/
	public void put(char[] data, bool reliable){
		if (data.length <=0)
			return;

		if (reliable)
			Reliable.put(data);
		else
			Unreliable.put([UNRELIABLE] ~data);
	}

	/**
        Reads data packet in same order as received from other end. 
        When there are no more left empty string is returned.
        */
	public char[] get(){
		return Received.get();
	}

	/**
	Decodes recieved raw UDP packet addressed to this end of peer.
	It translates it to data you can read with get() method.
	*/
	public void packetPut(char[] data){
		if (data.length <= 0)
			return;

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
	Returns raw UDP packet ready for you to transmit it to other end.
	This packet is encrypted data you have written with put() method.
	*/
	public public char[] packetGet(){
		// now sending procedures
		// procedure is - packets are sent from id's 0 - 249
		// packet 249 is repeatedly sent untill there is FINISHED from other end
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
	 Use for quick debug description of object (packet id's, number of packets received, waiting etc.).
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

		writefln("PeerQueue unittest PASS");
	}

}
