Guidelines
==========

This is port of enet networking library (http://enet.bespin.org) to Digital Mars D language.
You need enet.d module for import and to link with: 
  * enet.lib (static import lib for Windows compiled with DMC) 
  or
  * libenet.a (static import lib for Linux compiledon Fedora Core 3 with GCC)
  
With Windows compiling you will need extra libs: winmm.lib and ws2_32.lib.
Everything is defined in enet.d, so sheck the source.

For example you got client.d / server.d programs. Compile them with build_windows.bat scripts.

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