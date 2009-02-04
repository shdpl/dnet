import enet;
import std.stdio;

void main(){
  scope(exit) enet_deinitialize;

  assert(enet_initialize == 0);


    ENetHost * client;

    client = enet_host_create (null /* create a client host */,
                1 /* only allow 1 outgoing connection */,
                57600 / 8 /* 56K modem with 56 Kbps downstream bandwidth */,
                14400 / 8 /* 56K modem with 14 Kbps upstream bandwidth */);

    assert(client);

    ENetAddress address;
    ENetEvent event;
    ENetPeer *peer;

    /* Connect to some.server.net:1234. */
    enet_address_set_host (& address, "127.0.0.1");
    address.port = 1234;

    /* Initiate the connection, allocating the two channels 0 and 1. */
    peer = enet_host_connect (client, & address, 1);    
    
    assert(peer);
    
    // Wait up to 5 seconds for the connection attempt to succeed.
    if (enet_host_service (client, & event, 1000) > 0 && event.type == ENetEventType.ENET_EVENT_TYPE_CONNECT){
        writefln ("Connection to some.server.net:1234 succeeded.");


        // Send 10 hello packets.
        int i = 0;
        while(i < 10)        {
          i++;
            char[] s = "hello\0";
            ENetPacket *packet = enet_packet_create(s.ptr, s.length, ENetPacketFlag.ENET_PACKET_FLAG_RELIABLE);
          enet_peer_send(peer, 0, packet);

          enet_host_flush(client);
          
        }


    }

    else {
        // Either the 5 seconds are up or a disconnect event was
        // received. Reset the peer in the event the 5 seconds
        // had run out without any significant event.
        
        enet_peer_reset (peer);

        writefln ("Connection to some.server.net:1234 failed.");
    }



    enet_host_destroy(client);

}