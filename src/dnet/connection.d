/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

module dnet.connection;

import std.random;
import std.string;
import std.date;

import dnet.socket;
import dnet.fifo;
import dnet.buffer;

/**
Simple name for two-end points connection, where one is allways local address.
Remote addresse's port *might* not be the same after receiving response.
It is becouse other side might spawn new socket to communicate with calling side.
*/
public class DnetConnection {

	private {
		DnetSocket Socket;
		DnetAddress RemoteAddress;
		DnetFifo SendQueue;
		DnetFifo ReceiveQueue;
		long LastReceive;
		bool Connected;
		char[] Secret;
	}

	this(){
                Socket = new DnetSocket();
                SendQueue = new DnetFifo();
                ReceiveQueue = new DnetFifo();
		LastReceive = getUTCtime();
        }


	/**
	Connect to server (listening collection).
	Will use handshaking to get remote_address from new spawned socket on server side.
	*/
        public void connectToServer(DnetAddress remote_address){
                RemoteAddress = remote_address;
                // handshaking protocol
                // send packet to identify, expect same reply from real remote address
                Secret = format("%d", rand());
                send(new DnetBuffer(Secret));
                //send(new DnetBuffer(RemoteAddress.toString()));
                //send(new DnetBuffer(RemoteAddress.toString()));
                Connected = false;

	}
	public void connectToServer(DnetAddress local_address, DnetAddress remote_address){
		Socket.bind(local_address);
		connectToServer(remote_address);
	}

	/**
	Point to point connecting.
	*/
        public void connectToPoint(DnetAddress remote_address){
                RemoteAddress = remote_address;
                Connected = true;
        }

	public void connectToPoint(DnetAddress local_address, DnetAddress remote_address){
		Socket.bind(local_address);
		connectToPoint(remote_address);
	}


	public DnetAddress getLocalAddress(){
		return Socket.getLocalAddress();
	}
	public DnetAddress getRemoteAddress(){
		return RemoteAddress;
	}


	public void send(DnetBuffer buff){
		SendQueue.put(buff.getBuffer());
	}

	/**
	Reads next received data.
	*/
	public DnetBuffer receive(){
		return new DnetBuffer(ReceiveQueue.get());
	}

	/**
	Sends and receives data to other end.
	*/
	public void emit(){
		// receive
		DnetBuffer buff;
		DnetAddress addr;
		int size = Socket.receiveFrom(buff, addr);
		// todo - should check is received from RemoteAddress
		while(size > 0){
			LastReceive = getUTCtime();

			// connecting to server
			// untill connected, reply with secret is from remote address
			if (Connected == false && buff.getBuffer() == Secret){
				RemoteAddress = addr;
				Connected = true;
			}
			if (Connected == true && addr == RemoteAddress){
				ReceiveQueue.put(buff.getBuffer());
			}
			size = Socket.receiveFrom(buff, addr);
		}
		
		// transmit
		char[] tmp = SendQueue.get();
		while (tmp.length > 0){
			Socket.sendTo(new DnetBuffer(tmp), RemoteAddress);
			tmp = SendQueue.get();
		}
		
	}

	/**
	Time in miliseconds since last receive event.
	*/
	public uint lastReceive(){
		return ( (getUTCtime() - LastReceive) / TicksPerSecond ) * 1000;
	}

}
