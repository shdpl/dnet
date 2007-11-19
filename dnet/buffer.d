/**
	Copyright: (c) 2007 DNet Team
	Authors: DNet Team, see AUTHORS file
	License: MIT-style, see LICENSE file
*/
module dnet.buffer;

import dnet.utils;

/**
	Implements reading from a buffer.
*/
package struct DnetReader {
	alias read opCall;
	private {
		ubyte[]	contents;
		size_t	offset;
	}
	bool	overflowed;

	/// Constructor.
	void setContents( ubyte[] buffer ) {
		contents = buffer;
		offset = 0;
	}

	void clear() {
		offset = 0;
	}

	/// Returns slice of a valid content.
	ubyte[] slice() {
		return contents[0..offset];
	}

	ubyte[] getBytes( int numBytes ) {
		if ( offset + numBytes > contents.length ) {
			// underflow!
			overflowed = true;
			return null;
		}

		ubyte[] bytes = contents[offset..offset+numBytes];
		offset += numBytes;

		return bytes;
	}

	private void readImpl( T )( ref T v ) {
		auto data = getBytes( T.sizeof );
		if ( overflowed ) {
			v = v.init;
		}
		else {
			static if ( T.sizeof > 1 ) {
				v = dnetByteSwap( *cast( T * )data.ptr );
			}
			else {
				v = *cast( T * )data.ptr;
			}
		}
	}

	void read( ref ubyte c ) {
		readImpl( c );
	}

	void read( ref ushort s ) {
		readImpl( s );
	}

	void read( ref uint i ) {
		readImpl( i );
	}

	void read( ref int i ) {
		readImpl( i );
	}

	void read( ref ubyte[] b ) {
		ushort length;
		ubyte[] data;

		read( length );
		data = getBytes( length );
		if ( overflowed ) {
			b = null;
		}
		else {
			b = data;
		}
	}
}

/**
	Implements writing to a buffer.
*/
package struct DnetWriter {
	alias write opCall;
	private {
		ubyte[]	contents;
		size_t	offset;
	}
	bool	overflowed;

	/// Constructor.
	void setContents( ubyte[] buffer ) {
		contents = buffer;
		offset = 0;
	}

	void clear() {
		offset = 0;
	}

	/// Returns slice of a valid content.
	ubyte[] slice() {
		return contents[0..offset];
	}

	void putBytes( ubyte[] bytes ) {
		if ( offset + bytes.length > contents.length ) {
			overflowed = true;
			// overflow!
			if ( bytes.length > contents.length ) {
				return;
			}
			offset = 0;
		}

		contents[offset..offset+bytes.length] = bytes[];
		offset += bytes.length;
	}

	private void writeImpl( T )( T v ) {
		ubyte[T.sizeof]	data;
		static if ( T.sizeof > 1 ) {
			*cast( T * )data.ptr = dnetByteSwap( v );
		}
		else {
			data[0] = v;
		}
		putBytes( data );
	}

	void write( ubyte value ) {
		writeImpl( value );
	}

	void write( uint value ) {
		writeImpl( value );
	}

	void write( int value ) {
		writeImpl( value );
	}

	void write( ushort value ) {
		writeImpl( value );
	}

	void write( ubyte[] value ) {
		assert( value.length );
		write( cast( ushort )value.length );
		putBytes( value );
	}
}

unittest {
	ubyte[16]	buf;
	DnetWriter	write;
	DnetReader	read;

	write.setContents( buf );
	read.setContents( buf );

	const ubyte srcA = 1;
	const ushort srcB = 16;
	const uint srcC = 66000;
	const ubyte[] srcD = [ 1, 2, 3, 4 ];

	write( srcA );
	write( srcB );
	write( srcC );
	write( srcD );

	ubyte dstA;
	ushort dstB;
	uint dstC;
	ubyte[] dstD;

	read( dstA );
	read( dstB );
	read( dstC );
	read( dstD );
	
	assert( dstA == srcA );
	assert( dstB == srcB );
	assert( dstC == srcC );
	assert( dstD == srcD );
}
