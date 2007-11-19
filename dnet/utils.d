/**
	Copyright: (c) 2007 DNet Team
	Authors: DNet Team, see AUTHORS file
	License: MIT-style, see LICENSE file

	All (well, mostly all) OS/standard library-dependent code is gathered here.
*/
module dnet.utils;

version ( Tango ) {
	import tango.io.Stdout;
	import Integer = tango.text.convert.Integer;
	import tango.math.Random;
	import tango.core.ByteSwap;
	import tango.sys.Common;
}
else {
	import std.stdio;
	import std.conv;
	import std.random;
	import std.c.time;
}

/**
	Sleep for number of miliseconds.
*/
void dnetSleep( uint miliseconds ) {
	version ( Windows ) {
		version ( Tango ) {
			Sleep( miliseconds );
		}
		else {
			msleep( miliseconds );		
		}
	}
	else {
		usleep( miliseconds * 1000 );
	}
}

/**
	Prints text if compiled in debug mode.
*/
void debugPrint( char[] text ) {
	debug {
		version ( Tango ) {
			Stdout( text ).newline;
		}
		else {
			writefln( text );
		}
	}
}

/**
	Byte-swaps the data.
*/
T dnetByteSwap( T )( T a ) {
	version ( BigEndian ) {
		version ( Tango ) {
			// we swap to little-endian on big-endian machines
			static if ( T.sizeof == 4 ) {
				return ByteSwap.swap32( a );
			}
			else static if ( T.sizeof == 2 ) {
				return ByteSwap.swap16( a );
			}
			else {
				static assert( 0 );
			}
		}
		else {
			// this code came directly from std.stream
			static if ( T.sizeof == 2 ) {
				ubyte *startb = cast( ubyte * )a;
				ubyte x = *startb;
				*startb = *( startb + 1 );
				*( startb + 1 ) = x;
				
				return a;
			}
			else static if ( T.sizeof == 4 ) {
				return bswap( a );
			}
			else {
				static assert( 0 );
			}
		}
	}
	else {
		// on little-endian machines we do no swapping
		return a;
	}
}

/**
	toString/toUtf8 workaround not relying the PhobosCompatibility version.
*/
char[] typeToUtf8( T )( T a ) {
	version ( Tango ) {
		return a.toUtf8();
	}
	else {
		return a.toString();
	}
}

/**
	Splits s into tokens. Returns actual number of tokens.
*/
int splitIntoTokens( char[] s, char[][] tokens ) {
	int	pos;
	int	count;

	bool skipWhitespace() {
		while ( true ) {
			// skip whitespace
			while ( pos < s.length && s[pos] <= ' ' ) {
				pos++;
			}
			if ( pos == s.length ) {
				pos = -1;
				return false;
			}

			// an actual token
			break;
		}

		return true;
	}

	void readGeneric( ref char[] token ) {
		int		start = pos;

		while ( pos < s.length ) {
			if ( s[pos] <= ' ' ) {
				break;
			}

			pos++;
		}

		token = s[start..pos];
	}

	bool readString( ref char[] token ) {
		int		start, end;

		pos++;
		start = pos;
		while ( true ) {
			if ( pos == s.length ) {
				// missing trailing quote
				return false;
			}

			if ( s[pos] == '\"' ) {
				break;
			}

			pos++;
		}

		token = s[start..pos];
		pos++;	// step over the trailing quote

		return true;
	}

	// read all the tokens
	while ( true ) {
		if ( !skipWhitespace() ) {
			break;
		}

		char[]	token;

		if ( s[pos] == '"' ) {
			if ( !readString( token ) ) {
				break;
			}
		}
		else {
			readGeneric( token );
		}

		if ( count == tokens.length ) {
			break;
		}

		tokens[count] = token;
		count++;
	}

	return count;
}

unittest {
	char[]		string = "lengthy token sequence \"another lengthy token sequence\"";
	char[][64]	tokens;
	int			count = splitIntoTokens( string, tokens );

	assert( count == 4 );
	assert( tokens[0] == "lengthy" );
	assert( tokens[1] == "token" );
	assert( tokens[2] == "sequence" );
	assert( tokens[3] == "another lengthy token sequence" );
}

template BYTES2BITS( int n ) {
	const int BYTES2BITS = n << 3;
}

template BITS2BYTES( int n ) {
	const int BITS2BYTES = n >> 3;
}

unittest {
	int	a = BYTES2BITS!( 1 );
	assert( a == 8 );

	int b = BITS2BYTES!( 32 );
	assert( b == 4 );
}

/**
	Returns pseudo-random number.
*/
int dnetRand() {
	version ( Tango ) {
		return Random.shared.next( 65536 );
	}
	else {
		return rand() % 65536;
	}
}

/**
	ditto
*/
float dnetRandFloat() {
	return dnetRand() * ( 1.0f / 65536 );
}

/**
	Converts s to an integer.
*/
int dnetAtoi( char[] s ) {
	version ( Tango ) {
		return Integer.convert( s );
	}
	else {
		return toInt( s );
	}
}
