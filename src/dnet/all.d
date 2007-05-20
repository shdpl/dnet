/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

/**
Public classess you will use:
<ul>
<li><a href="server.html">DnetServer</a>
<li><a href="client.html">DnetClient</a>
</ul>
Private classess you don't need to know about:
<ul>
<li><a href="peer_queue.html">PeerQueue</a>
<li><a href="fifo_queue.html">FifoQueue</a>
</ul>
Comment:
By D's definition, char is "unsigned 8 bit". 
So char[] data or buffers are bytestreams, with char used as ubyte type.

TODO:
Make client/server use time window of 50ms for sending (not more frequent than 20 updates per sec)
& PeerQueue group packets into ~ 100 bytes chunks for optimal size and frequency of sending.
*/

module dnet.all;

public import dnet.client;
public import dnet.server;