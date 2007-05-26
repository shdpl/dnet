/*

Copyright (c) 2007 Branimir Milosavljevic <bane@3dnet.co.yu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

module dnet_new.socket;


import std.socket;
import std.c.time;

import dnet_new.buffer;


public void sleep(uint miliseconds){
	version(Windows)
		msleep(miliseconds);
	else
		usleep(miliseconds * 1000);
}

/**
*/
public class DnetAddress {

        private {
                InternetAddress Address;
        }

        /**
        Any local address.
        */
        this(ushort port){
                Address = new InternetAddress( port );
        }

        this(uint ip, ushort port){
                Address = new InternetAddress( ip, port );
        }

        this(char[] ip, ushort port){
                Address = new InternetAddress( ip, port );
        }

	public int opCmp(DnetAddress address){
		if (Address == address.Address)
			return 0;
		else
			return 1;
	}

        public char[] toString(){
                return Address.toString();
        }
}



/**
*/
public class DnetSocket {

	private {
		UdpSocket Socket;
	}

	this(){
		Socket = new UdpSocket(AddressFamily.INET);
		Socket.blocking(false);
	}

	public void bind(DnetAddress address){
		Socket.bind(address.Address);
	}

	public DnetAddress getLocalAddress(){
		InternetAddress a = cast(InternetAddress)Socket.localAddress();
		return new DnetAddress( a.addr(), a.port() );
	}

	public void sendTo(DnetBuffer buff, DnetAddress address){
		Socket.sendTo(buff.getBuffer(), address.Address);
	}

	public int receiveFrom(out DnetBuffer buff, out DnetAddress address){
		char[1024] tmp;
		Address addr;
		int size = Socket.receiveFrom(tmp, addr);
		if (size > 0)
			buff = new DnetBuffer(tmp[0..size].dup);
		address = new DnetAddress((cast(InternetAddress)addr).addr(), (cast(InternetAddress)addr).port());
		return size;
	}

}
