/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

module dnet.buffer;


/**
	A fancy name for byte buffer or ubyte[]
 */
package struct DnetBuffer {
	private {
		ubyte[]	buffer;
		size_t	bytesWritten;
		size_t	readingPos;
		bool	overflowed;
	}

	/// Constructor.
	static DnetBuffer opCall( ubyte[] theBuffer ) {
		DnetBuffer	buff;

		with ( buff ) {
			buffer = theBuffer;
			bytesWritten = 0;
		}

		return buff;
	}

	/// Returns true if buffer has been overflown.
	public bool isOverflowed() {
		return overflowed;
	}

	/// Sets reading counter to zero.
	public void beginReading( size_t start = 0 ) {
		readingPos = start;
	}

	/// Sets writing counter to zero.
	public void clear( size_t start = 0 ) {
		bytesWritten = start;
		readingPos = start;
	}

	/// Returns the number of bytes written.
	public uint length() {
		return bytesWritten;
	}

	/// Returns the overall size of the buffer.
	public size_t size() {
		return buffer.length;
	}

	/// Returns the number of bytes read.
	public size_t bytesRead() {
		return readingPos;
	}

	private void writeBytes( ubyte[] bytes ) {
		if ( bytesWritten + bytes.length > buffer.length ) {
			overflowed = true;
			// overflow!
			if ( bytes.length > buffer.length ) {
				return;
			}
			bytesWritten = 0;
		}

		buffer[bytesWritten..bytesWritten+bytes.length] = bytes[];
		bytesWritten += bytes.length;
	}

	private ubyte[] readBytes( int numBytes ) {
		if ( readingPos + numBytes > bytesWritten ) {
			// underflow!
			overflowed = true;
			return null;
		}

		ubyte[] bytes = buffer[readingPos..readingPos+numBytes];
		readingPos += numBytes;

		return bytes;
	}

	public void putData( ubyte[] data ) {
		writeBytes( data );
	}

	public void putUbyte( ubyte value ) {
		ubyte[1]	data = value;
		writeBytes( data );
	}

	public void putInt( int value ) {
		ubyte[4]	data;

		data[0] = value & 0xFF;
		data[1] = ( value >> 8 ) & 0xFF;
		data[2] = ( value >> 16 ) & 0xFF;
		data[3] = value >> 24; 

		writeBytes( data );
	}

	public void putUshort( ushort value ) {
		ubyte[2]	data;

		data[0] = value & 0xFF;
		data[1] = value >> 8;

		writeBytes( data );
	}

	public void putString( ubyte[] value )
	in {
		assert( value.length );
	}
	body {
		putUshort( value.length );
		writeBytes( value );
	}

	public ubyte readUbyte() {
		auto data = readBytes( 1 );
		if ( overflowed ) {
			return 0;
		}
		return data[0];
	}

	public uint readInt() {
		auto data = readBytes( 4 );
		if ( overflowed ) {
			return 0;
		}
		return data[0] + ( data[1] << 8 ) + ( data[2] << 16 ) + ( data[3] << 24 );
	}

	public ushort readUshort() {
		auto data = readBytes( 2 );
		if ( overflowed ) {
			return 0;
		}
		return data[0] + ( data[1] << 8 );
	}

	public ubyte[] readString() {
		size_t	length = readUshort();
		auto	data = readBytes( length );
		if ( overflowed ) {
			return null;
		}
		return data;
	}

	public ubyte[] dup(){
		return buffer[0..bytesWritten].dup;
	}

	public ubyte[] getBuffer() {
		return buffer[0..bytesWritten];
	}
}
