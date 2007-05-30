/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

module dnet.collection;

import dnet.socket;
import dnet.connection;
import dnet.fifo;
import dnet.buffer;


/**
A collection of connections.
This can be a server if you bind socket and listen 
or it can be a client connected to multiple points.

TODO:
When client connects new connection is spawned, 
thus client now gets answer not from port requested but from some new port.
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

	/**
	Make this collection act as a incoming server.
	*/
	public void bind(DnetAddress address){
		Socket.bind(address);
	}

	public DnetAddress getLocalAddress(){
		return Socket.getLocalAddress();
	}

	public void add(DnetAddress address){
		DnetConnection c = new DnetConnection();
		c.connectToPoint(address);
		Connections[address.toString()] = c;
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
		// this should handle only new requests that are redirected to new socket
		// all established connections are spawned on other socket
		DnetBuffer buff;
		DnetAddress addr;
		int size = Socket.receiveFrom(buff, addr);
		while(size > 0){
			if ((addr.toString() in Connections) == null){
				add(addr);
				// send back secret
				Connections[addr.toString()].send(buff);
			}
			size = Socket.receiveFrom(buff, addr);
		}

		// send & receive for each connection
		DnetBuffer tmp;
		foreach(DnetConnection c; Connections){
			c.emit(); // send & receive
			// move received data from connection's internal buffer 
			// to collections buffer
			// this is not smartest way and it is slow for sake of cleaness
			buff = c.receive();
			while (buff.length() > 0){
				ReceiveQueue.put(buff.getBuffer());
				tmp = c.receive();
			}
			
		}

		
	
	}

}
