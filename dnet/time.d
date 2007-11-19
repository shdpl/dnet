/**
	Copyright: (c) 2007 DNet Team
	Authors: DNet Team, see AUTHORS file
	License: MIT-style, see LICENSE file
*/
module dnet.time;

version ( Windows ) {
	extern ( Windows ) int GetTickCount();
}

/**
	Returns time elapsed since the start of app.
*/
package int currentTime() {
	version ( Windows ) {
		return GetTickCount;
	}
	else {
		static assert( 0 );
	}
}
