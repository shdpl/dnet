extern(C):

version(Windows){
  pragma(lib, "enet.lib");
  pragma(lib, "ws2_32.lib");
  pragma(lib, "winmm.lib");

  import std.c.windows.winsock;

  typedef void* ENetSocket;
  enum {
      ENET_SOCKET_NULL = INVALID_SOCKET
  }
}
else version(linux){
  pragma(lib, "libenet.a");

  typedef int ENetSocket;
  enum {
    ENET_SOCKET_NULL = -1
  }
}
else {
  static assert(0, "unsupported OS");
}



struct ENetBuffer {
    size_t dataLength;
    void * data;
}

// ==== callbacks.h ====


struct ENetCallbacks {
    void* function(size_t size) malloc;
    void function (void* memory) free;
    int function() rand;
}



/** @defgroup callbacks ENet internal callbacks
    @{
    @ingroup private
*/
void * enet_malloc (size_t);
void   enet_free (void *);
int    enet_rand ();


// ==== list.h ====

struct ENetListNode {
   ENetListNode* next;
   ENetListNode* previous;
}

typedef ENetListNode* ENetListIterator;

struct ENetList {
   ENetListNode sentinel;
}

void enet_list_clear (ENetList *);

ENetListIterator enet_list_insert (ENetListIterator, void *);
void * enet_list_remove (ENetListIterator);

size_t enet_list_size (ENetList *);

// ==== protocol.h ====

enum {
   ENET_PROTOCOL_MINIMUM_MTU             = 576,
   ENET_PROTOCOL_MAXIMUM_MTU             = 4096,
   ENET_PROTOCOL_MAXIMUM_PACKET_COMMANDS = 32,
   ENET_PROTOCOL_MINIMUM_WINDOW_SIZE     = 4096,
   ENET_PROTOCOL_MAXIMUM_WINDOW_SIZE     = 32768,
   ENET_PROTOCOL_MINIMUM_CHANNEL_COUNT   = 1,
   ENET_PROTOCOL_MAXIMUM_CHANNEL_COUNT   = 255,
   ENET_PROTOCOL_MAXIMUM_PEER_ID         = 0x7FFF
};

enum ENetProtocolCommand {
   ENET_PROTOCOL_COMMAND_NONE               = 0,
   ENET_PROTOCOL_COMMAND_ACKNOWLEDGE        = 1,
   ENET_PROTOCOL_COMMAND_CONNECT            = 2,
   ENET_PROTOCOL_COMMAND_VERIFY_CONNECT     = 3,
   ENET_PROTOCOL_COMMAND_DISCONNECT         = 4,
   ENET_PROTOCOL_COMMAND_PING               = 5,
   ENET_PROTOCOL_COMMAND_SEND_RELIABLE      = 6,
   ENET_PROTOCOL_COMMAND_SEND_UNRELIABLE    = 7,
   ENET_PROTOCOL_COMMAND_SEND_FRAGMENT      = 8,
   ENET_PROTOCOL_COMMAND_SEND_UNSEQUENCED   = 9,
   ENET_PROTOCOL_COMMAND_BANDWIDTH_LIMIT    = 10,
   ENET_PROTOCOL_COMMAND_THROTTLE_CONFIGURE = 11,
   ENET_PROTOCOL_COMMAND_COUNT              = 12,

   ENET_PROTOCOL_COMMAND_MASK               = 0x0F
}

enum ENetProtocolFlag {
   ENET_PROTOCOL_COMMAND_FLAG_ACKNOWLEDGE = (1 << 7),
   ENET_PROTOCOL_COMMAND_FLAG_UNSEQUENCED = (1 << 6),

   ENET_PROTOCOL_HEADER_FLAG_SENT_TIME = (1 << 15),
   ENET_PROTOCOL_HEADER_FLAG_MASK      = 0x8000
}

struct ENetProtocolHeader {
   uint checksum;
   ushort peerID;
   ushort sentTime;
}

struct ENetProtocolCommandHeader {
   ubyte command;
   ubyte channelID;
   ushort reliableSequenceNumber;
}

struct ENetProtocolAcknowledge {
   ENetProtocolCommandHeader header;
   ushort receivedReliableSequenceNumber;
   ushort receivedSentTime;
}

struct ENetProtocolConnect {
   ENetProtocolCommandHeader header;
   ushort outgoingPeerID;
   ushort mtu;
   uint windowSize;
   uint channelCount;
   uint incomingBandwidth;
   uint outgoingBandwidth;
   uint packetThrottleInterval;
   uint packetThrottleAcceleration;
   uint packetThrottleDeceleration;
   uint sessionID;
}

struct ENetProtocolVerifyConnect {
   ENetProtocolCommandHeader header;
   ushort outgoingPeerID;
   ushort mtu;
   uint windowSize;
   uint channelCount;
   uint incomingBandwidth;
   uint outgoingBandwidth;
   uint packetThrottleInterval;
   uint packetThrottleAcceleration;
   uint packetThrottleDeceleration;
}

struct ENetProtocolBandwidthLimit {
   ENetProtocolCommandHeader header;
   uint incomingBandwidth;
   uint outgoingBandwidth;
}

struct ENetProtocolThrottleConfigure {
   ENetProtocolCommandHeader header;
   uint packetThrottleInterval;
   uint packetThrottleAcceleration;
   uint packetThrottleDeceleration;
}

struct ENetProtocolDisconnect {
   ENetProtocolCommandHeader header;
   uint data;
}

struct ENetProtocolPing {
   ENetProtocolCommandHeader header;
}

struct ENetProtocolSendReliable {
   ENetProtocolCommandHeader header;
   ushort dataLength;
}

struct ENetProtocolSendUnreliable {
   ENetProtocolCommandHeader header;
   ushort unreliableSequenceNumber;
   ushort dataLength;
}

struct ENetProtocolSendUnsequenced{
   ENetProtocolCommandHeader header;
   ushort unsequencedGroup;
   ushort dataLength;
}

struct ENetProtocolSendFragment {
   ENetProtocolCommandHeader header;
   ushort startSequenceNumber;
   ushort dataLength;
   uint fragmentCount;
   uint fragmentNumber;
   uint totalLength;
   uint fragmentOffset;
}

union ENetProtocol {
   ENetProtocolCommandHeader header;
   ENetProtocolAcknowledge acknowledge;
   ENetProtocolConnect connect;
   ENetProtocolVerifyConnect verifyConnect;
   ENetProtocolDisconnect disconnect;
   ENetProtocolPing ping;
   ENetProtocolSendReliable sendReliable;
   ENetProtocolSendUnreliable sendUnreliable;
   ENetProtocolSendUnsequenced sendUnsequenced;
   ENetProtocolSendFragment sendFragment;
   ENetProtocolBandwidthLimit bandwidthLimit;
   ENetProtocolThrottleConfigure throttleConfigure;
}


// ==== enet.h ====

enum ENetVersion {
   ENET_VERSION = 1
}

enum ENetSocketType {
   ENET_SOCKET_TYPE_STREAM   = 1,
   ENET_SOCKET_TYPE_DATAGRAM = 2
}

enum ENetSocketWait {
   ENET_SOCKET_WAIT_NONE    = 0,
   ENET_SOCKET_WAIT_SEND    = (1 << 0),
   ENET_SOCKET_WAIT_RECEIVE = (1 << 1)
}

enum ENetSocketOption {
   ENET_SOCKOPT_NONBLOCK  = 1,
   ENET_SOCKOPT_BROADCAST = 2,
   ENET_SOCKOPT_RCVBUF    = 3,
   ENET_SOCKOPT_SNDBUF    = 4
}

enum {
   ENET_HOST_ANY       = 0,            /**< specifies the default server host */
   ENET_HOST_BROADCAST = 0xFFFFFFFF,   /**< specifies a subnet-wide broadcast */

   ENET_PORT_ANY       = 0             /**< specifies that a port should be automatically chosen */
}

/**
 * Portable internet address structure. 
 *
 * The host must be specified in network byte-order, and the port must be in host 
 * byte-order. The constant ENET_HOST_ANY may be used to specify the default 
 * server host. The constant ENET_HOST_BROADCAST may be used to specify the
 * broadcast address (255.255.255.255).  This makes sense for enet_host_connect,
 * but not for enet_host_create.  Once a server responds to a broadcast, the
 * address is updated from ENET_HOST_BROADCAST to the server's actual IP address.
 */
struct ENetAddress {
   uint host;
   ushort port;
};

/**
 * Packet flag bit constants.
 *
 * The host must be specified in network byte-order, and the port must be in
 * host byte-order. The constant ENET_HOST_ANY may be used to specify the
 * default server host.
 
   @sa ENetPacket
*/
enum ENetPacketFlag {
   /** packet must be received by the target peer and resend attempts should be
     * made until the packet is delivered */
   ENET_PACKET_FLAG_RELIABLE    = (1 << 0),
   /** packet will not be sequenced with other packets
     * not supported for reliable packets
     */
   ENET_PACKET_FLAG_UNSEQUENCED = (1 << 1),
   /** packet will not allocate data, and user must supply it instead */
   ENET_PACKET_FLAG_NO_ALLOCATE = (1 << 2)
}

//struct _ENetPacket;
typedef void function(ENetPacket* ) ENetPacketFreeCallback;

/**
 * ENet packet structure.
 *
 * An ENet data packet that may be sent to or received from a peer. The shown 
 * fields should only be read and never modified. The data field contains the 
 * allocated data for the packet. The dataLength fields specifies the length 
 * of the allocated data.  The flags field is either 0 (specifying no flags), 
 * or a bitwise-or of any combination of the following flags:
 *
 *    ENET_PACKET_FLAG_RELIABLE - packet must be received by the target peer
 *    and resend attempts should be made until the packet is delivered
 *
 *    ENET_PACKET_FLAG_UNSEQUENCED - packet will not be sequenced with other packets 
 *    (not supported for reliable packets)
 *
 *    ENET_PACKET_FLAG_NO_ALLOCATE - packet will not allocate data, and user must supply it instead
 
   @sa ENetPacketFlag
 */
struct ENetPacket {
   size_t                   referenceCount;  /**< internal use only */
   uint              flags;           /**< bitwise-or of ENetPacketFlag constants */
   ubyte*             data;            /**< allocated data for packet */
   size_t                   dataLength;      /**< length of data */
   ENetPacketFreeCallback   freeCallback;    /**< function to be called when the packet is no longer in use */
}

struct ENetAcknowledgement {
   ENetListNode acknowledgementList;
   uint  sentTime;
   ENetProtocol command;
}

struct ENetOutgoingCommand {
   ENetListNode outgoingCommandList;
   ushort  reliableSequenceNumber;
   ushort  unreliableSequenceNumber;
   uint  sentTime;
   uint  roundTripTimeout;
   uint  roundTripTimeoutLimit;
   uint  fragmentOffset;
   ushort  fragmentLength;
   ushort  sendAttempts;
   ENetProtocol command;
   ENetPacket * packet;
}

struct ENetIncomingCommand {  
   ENetListNode     incomingCommandList;
   ushort      reliableSequenceNumber;
   ushort      unreliableSequenceNumber;
   ENetProtocol     command;
   uint      fragmentCount;
   uint      fragmentsRemaining;
   uint *    fragments;
   ENetPacket *     packet;
}

enum ENetPeerState {
   ENET_PEER_STATE_DISCONNECTED                = 0,
   ENET_PEER_STATE_CONNECTING                  = 1,
   ENET_PEER_STATE_ACKNOWLEDGING_CONNECT       = 2,
   ENET_PEER_STATE_CONNECTION_PENDING          = 3,
   ENET_PEER_STATE_CONNECTION_SUCCEEDED        = 4,
   ENET_PEER_STATE_CONNECTED                   = 5,
   ENET_PEER_STATE_DISCONNECT_LATER            = 6,
   ENET_PEER_STATE_DISCONNECTING               = 7,
   ENET_PEER_STATE_ACKNOWLEDGING_DISCONNECT    = 8,
   ENET_PEER_STATE_ZOMBIE                      = 9 
}

const uint ENET_BUFFER_MAXIMUM = 1 + 2 * ENET_PROTOCOL_MAXIMUM_PACKET_COMMANDS;

enum {
   ENET_HOST_RECEIVE_BUFFER_SIZE          = 256 * 1024,
   ENET_HOST_SEND_BUFFER_SIZE             = 256 * 1024,
   ENET_HOST_BANDWIDTH_THROTTLE_INTERVAL  = 1000,
   ENET_HOST_DEFAULT_MTU                  = 1400,

   ENET_PEER_DEFAULT_ROUND_TRIP_TIME      = 500,
   ENET_PEER_DEFAULT_PACKET_THROTTLE      = 32,
   ENET_PEER_PACKET_THROTTLE_SCALE        = 32,
   ENET_PEER_PACKET_THROTTLE_COUNTER      = 7, 
   ENET_PEER_PACKET_THROTTLE_ACCELERATION = 2,
   ENET_PEER_PACKET_THROTTLE_DECELERATION = 2,
   ENET_PEER_PACKET_THROTTLE_INTERVAL     = 5000,
   ENET_PEER_PACKET_LOSS_SCALE            = (1 << 16),
   ENET_PEER_PACKET_LOSS_INTERVAL         = 10000,
   ENET_PEER_WINDOW_SIZE_SCALE            = 64 * 1024,
   ENET_PEER_TIMEOUT_LIMIT                = 32,
   ENET_PEER_TIMEOUT_MINIMUM              = 5000,
   ENET_PEER_TIMEOUT_MAXIMUM              = 30000,
   ENET_PEER_PING_INTERVAL                = 500,
   ENET_PEER_UNSEQUENCED_WINDOWS          = 64,
   ENET_PEER_UNSEQUENCED_WINDOW_SIZE      = 1024,
   ENET_PEER_FREE_UNSEQUENCED_WINDOWS     = 32,
   ENET_PEER_RELIABLE_WINDOWS             = 16,
   ENET_PEER_RELIABLE_WINDOW_SIZE         = 0x1000,
   ENET_PEER_FREE_RELIABLE_WINDOWS        = 8
}

struct ENetChannel {
   ushort  outgoingReliableSequenceNumber;
   ushort  outgoingUnreliableSequenceNumber;
   ushort  usedReliableWindows;
   ushort  reliableWindows [ENET_PEER_RELIABLE_WINDOWS];
   ushort  incomingReliableSequenceNumber;
   ENetList     incomingReliableCommands;
   ENetList     incomingUnreliableCommands;
}

/**
 * An ENet peer which data packets may be sent or received from. 
 *
 * No fields should be modified unless otherwise specified. 
 */
struct ENetPeer { 
   ENetHost* host;
   ushort   outgoingPeerID;
   ushort   incomingPeerID;
   uint   sessionID;
   ENetAddress   address;            /**< Internet address of the peer */
   void*        data;               /**< Application private data, may be freely modified */
   ENetPeerState state;
   ENetChannel * channels;
   size_t        channelCount;       /**< Number of channels allocated for communication with peer */
   uint   incomingBandwidth;  /**< Downstream bandwidth of the client in bytes/second */
   uint   outgoingBandwidth;  /**< Upstream bandwidth of the client in bytes/second */
   uint   incomingBandwidthThrottleEpoch;
   uint   outgoingBandwidthThrottleEpoch;
   uint   incomingDataTotal;
   uint   outgoingDataTotal;
   uint   lastSendTime;
   uint   lastReceiveTime;
   uint   nextTimeout;
   uint   earliestTimeout;
   uint   packetLossEpoch;
   uint   packetsSent;
   uint   packetsLost;
   uint   packetLoss;          /**< mean packet loss of reliable packets as a ratio with respect to the constant ENET_PEER_PACKET_LOSS_SCALE */
   uint   packetLossVariance;
   uint   packetThrottle;
   uint   packetThrottleLimit;
   uint   packetThrottleCounter;
   uint   packetThrottleEpoch;
   uint   packetThrottleAcceleration;
   uint   packetThrottleDeceleration;
   uint   packetThrottleInterval;
   uint   lastRoundTripTime;
   uint   lowestRoundTripTime;
   uint   lastRoundTripTimeVariance;
   uint   highestRoundTripTimeVariance;
   uint   roundTripTime;            /**< mean round trip time (RTT), in milliseconds, between sending a reliable packet and receiving its acknowledgement */
   uint   roundTripTimeVariance;
   ushort   mtu;
   uint   windowSize;
   uint   reliableDataInTransit;
   ushort   outgoingReliableSequenceNumber;
   ENetList      acknowledgements;
   ENetList      sentReliableCommands;
   ENetList      sentUnreliableCommands;
   ENetList      outgoingReliableCommands;
   ENetList      outgoingUnreliableCommands;
   ushort   incomingUnsequencedGroup;
   ushort   outgoingUnsequencedGroup;
   uint   unsequencedWindow [ENET_PEER_UNSEQUENCED_WINDOW_SIZE / 32]; 
   uint   disconnectData;
};

/** An ENet host for communicating with peers.
  *
  * No fields should be modified.

    @sa enet_host_create()
    @sa enet_host_destroy()
    @sa enet_host_connect()
    @sa enet_host_service()
    @sa enet_host_flush()
    @sa enet_host_broadcast()
    @sa enet_host_bandwidth_limit()
    @sa enet_host_bandwidth_throttle()
  */
struct ENetHost {
   ENetSocket         socket;
   ENetAddress        address;                     /**< Internet address of the host */
   uint        incomingBandwidth;           /**< downstream bandwidth of the host */
   uint        outgoingBandwidth;           /**< upstream bandwidth of the host */
   uint        bandwidthThrottleEpoch;
   uint        mtu;
   int                recalculateBandwidthLimits;
   ENetPeer *         peers;                       /**< array of peers allocated for this host */
   size_t             peerCount;                   /**< number of peers allocated for this host */
   uint        serviceTime;
   ENetPeer *         lastServicedPeer;
   int                continueSending;
   size_t             packetSize;
   ushort        headerFlags;
   ENetProtocol       commands [ENET_PROTOCOL_MAXIMUM_PACKET_COMMANDS];
   size_t             commandCount;
   ENetBuffer         buffers [ENET_BUFFER_MAXIMUM];
   size_t             bufferCount;
   ENetAddress        receivedAddress;
   ubyte         receivedData [ENET_PROTOCOL_MAXIMUM_MTU];
   size_t             receivedDataLength;
}

/**
 * An ENet event type, as specified in @ref ENetEvent.
 */
enum ENetEventType {
   /** no event occurred within the specified time limit */
   ENET_EVENT_TYPE_NONE       = 0,  

   /** a connection request initiated by enet_host_connect has completed.  
     * The peer field contains the peer which successfully connected. 
     */
   ENET_EVENT_TYPE_CONNECT    = 1,  

   /** a peer has disconnected.  This event is generated on a successful 
     * completion of a disconnect initiated by enet_pper_disconnect, if 
     * a peer has timed out, or if a connection request intialized by 
     * enet_host_connect has timed out.  The peer field contains the peer 
     * which disconnected. The data field contains user supplied data 
     * describing the disconnection, or 0, if none is available.
     */
   ENET_EVENT_TYPE_DISCONNECT = 2,  

   /** a packet has been received from a peer.  The peer field specifies the
     * peer which sent the packet.  The channelID field specifies the channel
     * number upon which the packet was received.  The packet field contains
     * the packet that was received; this packet must be destroyed with
     * enet_packet_destroy after use.
     */
   ENET_EVENT_TYPE_RECEIVE    = 3
}

/**
 * An ENet event as returned by enet_host_service().
   
   @sa enet_host_service
 */
struct ENetEvent {
   ENetEventType        type;      /**< type of the event */
   ENetPeer *           peer;      /**< peer that generated a connect, disconnect or receive event */
   ubyte           channelID; /**< channel on the peer that generated the event, if appropriate */
   uint          data;      /**< data associated with the event, if appropriate */
   ENetPacket *         packet;    /**< packet associated with the event, if appropriate */
}


/** 
  Initializes ENet globally.  Must be called prior to using any functions in
  ENet.
  @returns 0 on success, < 0 on failure
*/
int enet_initialize();

/** 
  Initializes ENet globally and supplies user-overridden callbacks. Must be called prior to using any functions in ENet. Do not use enet_initialize() if you use this variant.

  @param version the constant ENET_VERSION should be supplied so ENet knows which version of ENetCallbacks struct to use
  @param inits user-overriden callbacks where any NULL callbacks will use ENet's defaults
  @returns 0 on success, < 0 on failure
*/
int enet_initialize_with_callbacks (ENetVersion _version, ENetCallbacks* inits);

/** 
  Shuts down ENet globally.  Should be called when a program that has
  initialized ENet exits.
*/
void enet_deinitialize ();

/** @} */

/** @defgroup private ENet private implementation functions */

/**
  Returns the wall-time in milliseconds.  Its initial value is unspecified
  unless otherwise set.
  */
uint enet_time_get ();
/**
  Sets the current wall-time in milliseconds.
  */
void enet_time_set (uint);

/** @defgroup socket ENet socket functions
    @{
*/
ENetSocket enet_socket_create (ENetSocketType, ENetAddress *);
ENetSocket enet_socket_accept (ENetSocket, ENetAddress *);
int        enet_socket_connect (ENetSocket, ENetAddress *);
int        enet_socket_send (ENetSocket, ENetAddress *, ENetBuffer *, size_t);
int        enet_socket_receive (ENetSocket, ENetAddress *, ENetBuffer *, size_t);
int        enet_socket_wait (ENetSocket, uint *, uint);
int        enet_socket_set_option (ENetSocket, ENetSocketOption, int);
void       enet_socket_destroy (ENetSocket);

/** @} */

/** @defgroup Address ENet address functions
    @{
*/
/** Attempts to resolve the host named by the parameter hostName and sets
    the host field in the address parameter if successful.
    @param address destination to store resolved address
    @param hostName host name to lookup
    @retval 0 on success
    @retval < 0 on failure
    @returns the address of the given hostName in address on success
*/
int enet_address_set_host (ENetAddress * address, char * hostName);

/** Gives the printable form of the ip address specified in the address parameter.
    @param address    address printed
    @param hostName   destination for name, must not be NULL
    @param nameLength maximum length of hostName.
    @returns the null-terminated name of the host in hostName on success
    @retval 0 on success
    @retval < 0 on failure
*/
int enet_address_get_host_ip (ENetAddress * address, char * hostName, size_t nameLength);

/** Attempts to do a reverse lookup of the host field in the address parameter.
    @param address    address used for reverse lookup
    @param hostName   destination for name, must not be NULL
    @param nameLength maximum length of hostName.
    @returns the null-terminated name of the host in hostName on success
    @retval 0 on success
    @retval < 0 on failure
*/
int enet_address_get_host (ENetAddress * address, char * hostName, size_t nameLength);

/** @} */

ENetPacket * enet_packet_create ( void *, size_t, uint);
void         enet_packet_destroy (ENetPacket *);
int          enet_packet_resize  (ENetPacket *, size_t);
uint    enet_crc32 ( ENetBuffer *, size_t);
                
ENetHost * enet_host_create ( ENetAddress *, size_t, uint, uint);
void       enet_host_destroy (ENetHost *);
ENetPeer * enet_host_connect (ENetHost *, ENetAddress *, size_t);
int        enet_host_check_events (ENetHost *, ENetEvent *);
int        enet_host_service (ENetHost *, ENetEvent *, uint);
void       enet_host_flush (ENetHost *);
void       enet_host_broadcast (ENetHost *, ubyte, ENetPacket *);
void       enet_host_bandwidth_limit (ENetHost *, uint, uint);
void       enet_host_bandwidth_throttle (ENetHost *);

int                 enet_peer_send (ENetPeer *, ubyte, ENetPacket *);
ENetPacket *        enet_peer_receive (ENetPeer *, ubyte);
void                enet_peer_ping (ENetPeer *);
void                enet_peer_reset (ENetPeer *);
void                enet_peer_disconnect (ENetPeer *, uint);
void                enet_peer_disconnect_now (ENetPeer *, uint);
void                enet_peer_disconnect_later (ENetPeer *, uint);
void                enet_peer_throttle_configure (ENetPeer *, uint, uint, uint);
int                   enet_peer_throttle (ENetPeer *, uint);
void                  enet_peer_reset_queues (ENetPeer *);
ENetOutgoingCommand * enet_peer_queue_outgoing_command (ENetPeer *, ENetProtocol *, ENetPacket *, uint, ushort);
ENetIncomingCommand * enet_peer_queue_incoming_command (ENetPeer *, ENetProtocol *, ENetPacket *, uint);
ENetAcknowledgement * enet_peer_queue_acknowledgement (ENetPeer *, ENetProtocol *, ushort);

size_t enet_protocol_command_size (ubyte);
