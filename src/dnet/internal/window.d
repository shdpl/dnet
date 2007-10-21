/*

Copyright (c) 2007 Dmitry Shalkhakov <dmitry dot shalkhakov at gmail dot com>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

module dnet.internal.window;

/**
	Sliding window struct for reliable data buffering.
	FIXME: actually, it's a circular array, but I couldn't find a simple name for it =).
*/
struct DnetWindow {
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
