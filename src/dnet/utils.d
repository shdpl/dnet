/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

module dnet.utils;


import std.c.time;
import std.date;

/**
Sleep for number of miliseconds.
*/
public void DnetSleep(uint miliseconds){
	version(Windows)
		msleep(miliseconds);
	else
		usleep(miliseconds * 1000);
}

/**
Returns number of miliseconds passed since last call of this func.
*/
public uint DnetTime(){
	static long t = 0;
	if (t == 0)
		t = getUTCtime();
	long old = t;
	t = getUTCtime();
	return cast(uint) ( (t - old) / (TicksPerSecond / 1000) );
	//return 0;
}

/*
Splits s into tokens.
*/
package char[][] splitIntoTokens( char[] s ) {
	int			pos;
	char[][]	tokens;

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

		tokens ~= token;
	}

	return tokens;
}

unittest {
	char[]	string = "lengthy token sequence \"another lengthy token sequence\"";
	char[][]	tokens = string.splitIntoTokens();

	assert( tokens.length == 4 );
	assert( tokens[0] == "lengthy" );
	assert( tokens[1] == "token" );
	assert( tokens[2] == "sequence" );
	assert( tokens[3] == "another lengthy token sequence" );
}
