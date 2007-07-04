/*
	Written by Dmitry Shalkhakov
*/

module dnet.internal.window;

/**
	Sliding window struct for reliable data buffering.
	FIXME: actually, it's a circular array, but I couldn't find a simple name for it =).
*/
private struct DnetWindow {
	private {
		ubyte[][]	queue;
		int			sequence;
	}

	static DnetWindow opCall( int windowSize ) {
		DnetWindow	window;

		with ( window ) {
			queue.length = windowSize;
		}

		return window;
	}

	public void clear() {
		sequence = 0;
	}

	public int putSequence() {
		return sequence;
	}

	public void put( ubyte[] buff ) {
		sequence++;
		size_t	index = sequence & ( queue.length - 1 );
		if ( queue[index] !is null ) {
			delete queue[index];
		}
		queue[index] = buff.dup;
	}

	public ubyte[] get( int sequence ) {
		return queue[sequence & ( queue.length - 1 )];
	}
}
