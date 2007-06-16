/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

module dnet.buffer;


/**
A fancy name for byte buffer or char[]
*/
public class DnetBuffer {


	private {
		char[]	Buff;
		uint	Length = 0;
	}

	this(){
	}

	this(char[] buff){
		Buff = buff;
		Length = buff.length;
	}

	public uint length(){
		return Buff.length;
	}

	//public void put(char value){}
	//public void put(short value){}
	//public void put(ushort value){}
	//public void put(int value){}
	//public void put(uint value){}
	//public void put(char[] value){}
	//public int readInt(uint pos){}
	//public uint readUint(uint pos){}

	public char[] dup(){
		return Buff[0..Length].dup;
	}

	public char[] buffer() {
		return Buff[0..Length];
	}

}
