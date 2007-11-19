/**
	Copyright: (c) 2007 DNet Team
	Authors: DNet Team, see AUTHORS file
	License: MIT-style, see LICENSE file
*/
module dnet.fifo;

/**
	A simple FIFO container. Overflow will not happen as capacity will only grow. Underflow is
	handled by returning null. Unused data is overwritten, not cleaned up.
*/
struct DnetFifo( T, int size ) {
	private {
		int		capacity;
		int		first, last;
		T[size]	base;
		T[]		buffer;
	}

	int		length;

	/**
		Initializes container. Be sure to call prior to using.
	*/
	void init() {
		capacity = size;
		buffer = base;
	}

	/**
		Stores a reference to data.
	*/
	void put( T data ) {
		if ( length == capacity ) {
			capacity *= 2;

			auto newBuf = new T[capacity];
			newBuf[0..buffer.length] = buffer[];

			if ( buffer !is base ) {
				delete buffer;
			}

			buffer = newBuf;
		}

		buffer[last] = data;
		length++;

		if ( last == capacity - 1 ) {
			last = 0;
		}
		else {
			last++;
		}
	}

	/**
		Gets data. If no more left, returns null.
	*/
	T get() {
		T	s = null;

		if ( length > 0 ) {
			length--;
			s = buffer[first];
			if ( first == capacity - 1 ) {
				first = 0;
			}
			else {
				first++;
			}
		}

		return s;
	}
}
