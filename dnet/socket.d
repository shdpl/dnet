/**
	Copyright: (c) 2007 DNet Team
	Authors: DNet Team, see AUTHORS file
	License: MIT-style, see LICENSE file

	DNet does not introduce any abstractions ontop network layer provided by a standard library.
	This module only encapsulates differences between Phobos and Tango socket interfaces.
*/
module dnet.socket;

version ( Tango ) {
	public import tango.net.Socket;
}
else {
	public import std.socket;
	alias InternetAddress IPv4Address;

	version ( Windows ) {
		pragma(lib, "ws2_32.lib");
		pragma(lib, "wsock32.lib");
	}
}
