#!/bin/bash

DMD="/dmd/dmd/bin/dmd"
LIB="src/dnet.d src/dogslow.d"

rm -f bin/*
$DMD examples/dogslow/hello_world/client.d $LIB -ofbin/dogslow_hello_world_client
$DMD examples/dogslow/hello_world/server.d $LIB -ofbin/dogslow_hello_world_server

$DMD examples/dogslow/objects/client.d $LIB -ofbin/dogslow_objects_client
$DMD examples/dogslow/objects/server.d $LIB -ofbin/dogslow_objects_server

echo "Building documentation. Check ./api folder."
$DMD -c src/dnet.d src/dogslow.d -Ddapi

rm -f client.o
rm -f server.o
rm -f dnet.o
rm -f dogslow.o


echo "Examples are build. Check ./bin folder."
