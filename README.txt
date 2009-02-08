Guidelines
==========

This is D port of enet library (http://enet.bespin.org).
You'll need import enet.d to your project and link it with: 
  * lib/enet.lib (static import lib for Windows compiled with DMC) 
    or
  * lib/libenet.a (static import lib for Linux compiled on Fedora Core 3 with GCC)
  
On Windows you'll need extra libs: winmm.lib and ws2_32.lib.
Everything is defined in enet.d, so sheck the source.

Example can be found in client.d/server.d programs. Compile them with build_windows.bat scripts.

Also, use docs from enet_docs folder as your primary learning info.

Have a nice coding.


Project history
===============

Warning: some bad English ahead:


Some time ago, in the galaxy a far, far away, a young development team (actually, 1 guy that was joined by another guy later) wanted to make from scratch The ultra-giga-mega fast networking library for games in their favourite language - Digital Mars D. They were young, foolish and enthusiastic then (some of it now, too). Neadless to say, they failed miserabely.

Then they got little older and smarter and decided to port to Language D an already existing ultra-giga-mega fast networking library written in C, called enet (http://enet.bespin.org).


Ex-Dnet Team (in order of appearance):
======================================

Branimir Milosavljevic <branimir.milosavljevic@gmail.com>
Dmitry Shalkhakov <dmitry dot shalkhakov at gmail dot com>