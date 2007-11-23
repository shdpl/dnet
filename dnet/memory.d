/**
	Copyright: (c) 2007 DNet Team
	Authors: DNet Team, see AUTHORS file
	License: MIT-style, see LICENSE file

	Memory allocations/deallocations.
*/
module dnet.memory;

struct DnetAllocator {
	ubyte[] alloc( int size ) {
		return new ubyte[size];
	}

	ubyte[] duplicate( ubyte[] src ) {
		auto dst = alloc( src.length );
		dst[] = src[];
		return dst;
	}

	void free( ref ubyte[] data ) {
		delete data;
	}
	
	void free( ref char[] data ) {
		delete data;
	}
}
