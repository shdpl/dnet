import enet;
import std.stdio;

void main(){
  scope(exit) enet_deinitialize;

  assert(enet_initialize == 0);

  
  ENetAddress address;
  ENetHost* server;

  /* Bind the server to the default localhost.
   * A specific host address can be specified by
   * enet_address_set_host (& address, "x.x.x.x");
   */
  enet_address_set_host (&address, "127.0.0.1");
  /* Bind the server to port 1234. */
  address.port = 1234;
  

  server = enet_host_create (& address /* the address to bind the server host to */, 
              32 /* allow up to 32 clients and/or outgoing connections */,
              0 /* assume any amount of incoming bandwidth */,
              0 /* assume any amount of outgoing bandwidth */);
  
  assert(server); // must be non null
  

  
  writefln("start");  
  while(true){
        writefln("check");    

    ENetEvent event;
  
    /* Wait up to 1000 milliseconds for an event. */
    while (enet_host_service (server, &event, 1000) > 0){
        writefln("GOT packet");
        switch (event.type){
          case ENetEventType.ENET_EVENT_TYPE_CONNECT:
              writefln ("A new client connected from %d:%d.\n", 
                      event.peer.address.host,
                      event.peer.address.port);

              /* Store any relevant client information here. */
              event.peer.data = "Client information".dup.ptr;

              
              break;

          case ENetEventType.ENET_EVENT_TYPE_RECEIVE:
              writefln ("A packet of length %d containing %s was received from %s on channel %d.\n",
                      event.packet.dataLength,
                      event.packet.data,
                      event.peer.data,
                      event.channelID);

              /* Clean up the packet now that we're done using it. */
              enet_packet_destroy (event.packet);
              
              break;
             
          case ENetEventType.ENET_EVENT_TYPE_DISCONNECT:
              writefln ("%s disconected.\n", event.peer.data);

              /* Reset the peer's client information. */

              event.peer.data = null;
              break;
          default:
            writefln("unknown packet");
        } // switch
        
      } // while packet

  } // while true

  enet_host_destroy(server);
}