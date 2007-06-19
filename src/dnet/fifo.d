/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/


module dnet.fifo;

private import std.stdio;
private import std.string;

/**
 Auto resizeable FIFO (First In First Out) container that stores char[] type of unlimited length.
 Overflow shouldn't happen becouse capacity will grow. 
 Underflow is handled by returning empty string.
 Capacity can only grow and unused data is overwritten, not cleaned up.

 TODO:
  if canister could shrink unneededcapacity , 
  free unused indexes to reduce memory load
*/
public class DnetFifo {
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

	/**
	Stores string.
	*/
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

	/**
	Gets string. If no more left, return empty string.
	*/
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
	public char[] toString(){
		return format("<FifoQueue - capacity %d length %d first %d last %d>", Capacity, Length, First, Last);
	}

	unittest {
		DnetFifo q = new DnetFifo();
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
		writefln("DnetFifo unittest PASS");
	}

}
