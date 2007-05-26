#!/bin/bash

DMD=/dmd/dmd/bin/dmd
LIB="dnet_new/buffer.d dnet_new/socket.d dnet_new/connection.d dnet_new/fifo.d dnet_new/collection.d"


$DMD server.d $LIB
$DMD client.d $LIB

rm *.o
