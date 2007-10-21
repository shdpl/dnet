/*

Copyright (c) 2007 Branimir Milosavljevic <branimir.milosavljevic@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/


module dnet.fifo;

version ( Tango ) {
	private import tango.io.Stdout;
}
else {
	private import std.stdio;
	private import std.string;
}

/**
	Auto resizeable FIFO (First In First Out) container that stores ubyte[] type of unlimited length.
	Overflow shouldn't happen becouse capacity will grow. 
	Underflow is handled by returning empty string.
	Capacity can only grow and unused data is overwritten, not cleaned up.

	TODO:
	if canister could shrink unneededcapacity , 
	free unused indexes to reduce memory load
	TODO: in fact, buffers should be statically allocated, and buffer overflow is an error
*/
public struct DnetFifo {
	private uint Capacity;
	private ubyte[][] Buff;
	private uint First;
	private uint Last;
	private uint Length;

	static DnetFifo opCall() {
		DnetFifo	fifo;

		with ( fifo ) {
			First = 0;
			Last = 0;
			Capacity = 16; // start with default capacity
			Length = 0;
			Buff.length = Capacity;
		}

		return fifo;
	}

	/**
	Stores string.
	*/
	public void put(ubyte[] data){
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

	/**
	Gets string. If no more left, return empty string.
	*/
	public ubyte[] get(){
		ubyte[] s = null; // we handle underflows by returning empty string
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

	/**
	Number of stored strings at the moment (number of get() methods you can perform).
	*/
	public uint length(){
		return Length;
	}

	/**
	Max number of strings canister can store at the moment. 
	It will grow automatically if space is needed.
	Starting capacity is 16 and grows by factor 2 (doubles).
	*/
	public uint capacity(){
		return Capacity;
	}

	/**
	Returns convenient debug message describing object (capacity, length, position of indexes etc.).
	*/
	version ( Tango ) {
		public char[] toUtf8(){
			return "";
		}
	}
	else {
		public char[] toString(){
			return format("<FifoQueue - capacity %d length %d first %d last %d>", Capacity, Length, First, Last);
		}
	}

	unittest {
		auto q = DnetFifo();
		assert(q.get().length == 0 );
		assert(q.length == 0);
		q.put(cast(ubyte[])"things you can resist");
		q.put(cast(ubyte[])"things you cannot");
		q.put(cast(ubyte[])"they're just framed in blood");
		assert(q.length == 3);
		assert(cast(char[])q.get() == "things you can resist");
		assert(q.length == 2);
		assert(cast(char[])q.get() == "things you cannot");
		assert(cast(char[])q.get() == "they're just framed in blood");
		assert(cast(char[])q.get() == "");
		assert(q.length == 0);
		for(int i=0; i < 1024; i++){
			q.put(cast(ubyte[])"a");
			assert(cast(char[])q.get() == "a");
		}
		version ( Tango ) {
			Stdout("DnetFifo unittest PASS\n");
		}
		else {
			writefln("DnetFifo unittest PASS");
		}
	}

}
