/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

module dnet.socket;


import std.socket;

/**
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
		Socket.getLocalAddress();
	}
	public DnetAddress getRemoteAddress(){
		return RemoteAddress;
	}


	public void send(DnetByteBuffer buff){
		Send.Queue.put(buff.getBuffer());
	}

	/**
	Reads next received data.
	*/
	public DnetBuffer DnetByteBuffer receive(){
	}

	/**
	Sends and receives data.
	*/
	public void emit(){
	}

	/**
	Time in miliseconds since last receive.
	*/
	public uint lastReceive(){
	}

}