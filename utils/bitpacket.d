/// Utility for creating bit accurate instead of byte sized packets.
/// See unittest section at the bottom.

import std.bitarray;
import std.stdio;
import std.math;

/// BitPacket that can contain values (numbers and strings) of bit precision (not byte).
/// Header is 1 or 4 bytes long and contains length of data part.
/// If data part length is less tha 128, then header is 1 byte, otherwise it is 4 bytes long.
/// Maximum packet data length is 127*256^3 ~= 2.1gb
class BitPacket {
  BitArray a;
  uint idx;  // current index
  uint size; // number of bits used

  /// Creates empty packet.
  this(){
    idx = 0;
    size = 0;
    a.length = 64;
  }

  /// Creates packet and populates data. Pointer is set at the begining.
  this(ubyte[] data){
    idx = 0;
    a.init(data.dup, data.length * 8);
    size = data.length * 8;
  }

  /// Checks if array cann accept this number of bits and resizes it if needed. Should be called before write.
  private void checkSize(uint len){
    if (idx + len > a.length)
      a.length = a.length + len + 64;
  }
  
  /// Append bit translation of number to array. If signed then extra bit will be inserted as first. Value is compacted in number of bits.
  void add(long value, bool signed, uint bits){
    if (bits <= 0) return;
    
    if (signed)
      add(value < 0 ? 1 : 0, false, 1);
    if (value < 0) value = -value;
    
    checkSize(bits);
    ulong max_value = (1 << bits) - 1;
    //writefln(max_value);
    if (value > max_value)
      value = max_value;
    
    for(int i=bits-1;i>=0;i--){
      //writefln(i);
      //writefln(value, " ", value > (1 << i));
      a[idx + i] = value % 2 == 1;
      value = value >> 1;
      
    }
    idx += bits;
    size += bits;
  }

  /// Retrieves number from array.
  long get(bool signed, uint bits){
    assert(idx + bits + (signed ? 1 : 0) <= size);
    long tmp = 0;
    bool negative = signed ? (a[idx++] == 1) : false;
    int exp = bits - 1;
    for(int i=0; i<bits; i++){
      tmp += a[idx+i] << exp--;
    }
    idx += bits;
    return negative ? -tmp : tmp;
  }
  
  /// Append string as byte array. First two bytes are string length.
  void add(char[] value){
    if (value.length == 0) return;
    assert(value.length < ushort.max);
    add(value.length, false, 16); // write string length in bytes
    
    checkSize(value.length * 8);
    BitArray tmp;
    tmp.init(value, value.length * 8);
    foreach(b; tmp){
      a[idx++] = b;
    }
    size += value.length * 8;
  }
  
  /// Retreives string.
  char[] get(){
    assert(idx + 16 <= size);
    long len = get(false, 16);
    assert(idx + len*8 <= size);
    
    BitArray tmp;
    tmp.length = len*8;
    for(int i=0; i<len*8; i++)
      tmp[i] = a[idx++];

    void[] v = (cast(void[])tmp)[0 .. len];
    return cast(char[]) v;
    
  }


  

  /// Creates header and dumps packet in array of bytes ready for network transmittion etc.
  /// It rounds length to byte size.
  ubyte[] dump(){
    int data_length = cast(int)((size + 7) / 8); // number of bytes of data
    void[] tmp = (cast(void[])a)[0 .. data_length];
    
    // make header
    ubyte[] header;
    if (data_length < 128)
      header = [data_length];
    else if (data_length < int.max) {
      int i = -data_length;
      header = *cast(ubyte[4]*)(&i); // first bit (sign flag) will be 1 becouse it is negative
    }
    else 
      assert(0, "packet data too big");
      
    
    return header ~ cast(ubyte[])tmp;
  }

  /// Extracts packets from begining of stream, and return them as array. Stream is shortened.
	static BitPacket[] extract(ref ubyte[] stream){
    BitPacket[] packets;
    while(true){
      if (stream.length > 0){
        // get header length
        int data_length;
        int header_length = 0;
        ubyte u = *(cast(ubyte*)(stream.ptr));
        if (u < 128){
          data_length = u;
          header_length = 1;
        }
        else {
          data_length = -*(cast(int*)stream.ptr);
          header_length = 4;
        }
        
        
        if (stream.length >= header_length + data_length){
          BitPacket p = new BitPacket(stream[header_length .. header_length + data_length]);
          packets ~= p;
          stream = stream[header_length + data_length .. $];
        }
        else
          break;
      }
      else
        break;
    }
    return packets;
	}

  char[] toString(){
    char[] s;
    for(int i=0; i<a.length; i++){
      if (i%8 == 0)
        s ~= " ";
      s ~= a[i] ? "1" : "0";
    }
    return s;
  }

}

unittest {
  ubyte[] s; // stream for sending ower network etc.

  char[] tmp_string;
  tmp_string.length = 256; // make it bigger than 127

  BitPacket p0 = new BitPacket; // first packet
  p0.add(3, true, 3); // add some integer, see function description for details
  p0.add(-5, true, 3);
  p0.add("1234567890"); // add some string
  s ~= p0.dump; // append bytes to stream

  BitPacket p1 = new BitPacket;
  p1.add(66, false, 7); // store number 66 as unsigned int with exaclty 7 bits of storage space
  p1.add("HELLO!");
  p1.add(-34567, true, 25); // store negative number as signed, with 25 bits for value (1 extra bit will be used becouse of signed)
  p1.add(tmp_string); // use big string to test packet size > 127
  s ~= p1.dump;

  BitPacket[] ps = BitPacket.extract(s); // packet decoding, removes decoded bytes from stream
  assert(s.length == 0);
  assert(ps.length == 2);
  
  assert(ps[0].get(true, 3) == 3); // order of value retreiving MUST be the same as when adding them
  assert(ps[0].get(true, 3) == -5);
  assert(ps[0].get == "1234567890");
 
  assert(ps[1].get(false, 7) == 66);
  assert(ps[1].get == "HELLO!");
  assert(ps[1].get(true, 25) == -34567);
  assert(ps[1].get == tmp_string);
  
  writefln("unittest BitPacket OK");
}  

// in case if you want to compile this module standalone  
void main(){
}