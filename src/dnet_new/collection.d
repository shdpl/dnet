/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

module dnet_new.collection;

import std.stdio;


import dnet_new.socket;
import dnet_new.buffer;
import dnet_new.fifo;
import dnet_new.connection;

/**
A kind of a funny name for a server - or in other words a collection of connections.
*/
public class DnetCollection {

	private {
		DnetSocket Socket;

		DnetConnection[char[]] Connections;

		DnetFifo ReceiveQueue;
	}

	/**
	
	*/
	this(){
		Socket = new DnetSocket();

		ReceiveQueue = new DnetFifo();
	}

	public void bind(DnetAddress address){
		Socket.bind(address);
	}

	public DnetAddress getLocalAddress(){
		return Socket.getLocalAddress();
	}

	public void add(DnetAddress address){
		Connections[address.toString()] = new DnetConnection(address);
	}

	public DnetConnection[char[]] getAll(){
		return Connections;
	}

	public void broadcast(DnetBuffer buff){
		foreach(DnetConnection c; Connections)
			c.send(buff);
	}

	/**
	Reads next received data.
	*/
	public DnetBuffer receive(){
		char[] tmp = ReceiveQueue.get();
		return new DnetBuffer(tmp);
	}

	/**
	Sends and receives data.
	*/
	public void emit(){
		// todo - reorganize this part. each connection receives on emit()
		// if collection listens here first then.... oh man, it is just so complicated...

		// receive
		DnetBuffer buff;
		DnetAddress addr;
		int size = Socket.receiveFrom(buff, addr);
		while(size > 0){
			ReceiveQueue.put(buff.getBuffer());
			if ((addr.toString() in Connections) == null)
				add(addr);
			size = Socket.receiveFrom(buff, addr);
		}

		// send
		foreach(DnetConnection c; Connections)
			c.emit();
	
	}

}
