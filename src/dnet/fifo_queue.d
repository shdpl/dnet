module dnet.fifo_queue;

private import std.stdio;
private import std.string;

/**
 Auto resizeable FIFO container that stores char[] type.
 Overflow shouldn't happen becouse capacity will grow. 
 Underflow is handled by returning empty string.
 Capacity can only grow and unused data is overwritten, not cleaned up.

 Toward perfection: if canister could shrink capacity if not needed anymore and to be able to free memory from unused indexes.
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
