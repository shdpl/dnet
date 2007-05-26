/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

module dnet.connection;

import dnet.socket;
import dnet.fifo;
import dnet.buffer;

/**
Simple name for two-end points connection, where one is allways local address.
*/
public class DnetConnection {

	private {
		DnetSocket Socket;
		DnetAddress RemoteAddress;

		DnetFifo SendQueue;
		DnetFifo ReceiveQueue;
	}

	/**
	
	*/
	this(DnetAddress remote_address){
		Socket = new DnetSocket();
		RemoteAddress = remote_address;

		SendQueue = new DnetFifo();
		ReceiveQueue = new DnetFifo();
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
	Sends and receives data.
	*/
	public void emit(){
		// receive
		DnetBuffer buff;
		DnetAddress addr;
		int size = Socket.receiveFrom(buff, addr);
		// todo - should check is received from RemoteAddress
		while(size > 0 /* && addr == RemoteAddress*/){
			ReceiveQueue.put(buff.getBuffer());
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
	Time in miliseconds since last receive.
	*/
	public uint lastReceive(){
		return 0; // todo
	}

}
