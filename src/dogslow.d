/**
*/
module dogslow;

private import dnet;


///
class DogObject {
///
	this(){
	}
///
	~this(){
	}

///
	char[] getClassName() {
		return "";
	}
///
	uint getObjectId() {
		return 0;
	}

///
	void setString(char[] property_name, char[] value, bool replicate=true){
	}
///
	void setByte(char[] property_name, byte value, bool replicate=true){
	}
///
	void setShort(char[] property_name, short value, bool replicate=true){
	}
///
	void setInt(char[] property_name, int value, bool replicate=true){
	}
///
	void setFloat(char[] property_name, float value, bool replicate=true){
	}
///
	void setVector3f(char[] property_name, float[3] value, bool replicate=true){
	}
///
	void setPointer(char[] property_name, void* value){
	}
///	
	char[] getString(char[] property_name){
		return "";
	}
///
	byte getByte(char[] property_name){
		return 0;
	}
///
	short getShort(char[] property_name){
		return 0;
	}
///
	int getInt(char[] property_name){
		return 0;
	}
///
	float getFloat(char[] property_name){
		return 0.0;
	}
///
	float[] getVector3f(char[] property_name){
		return [0,0,0];
	}
///
	void* getPointer(char[] property_name){
		return null;
	}
}

///
public class DogBase {
	protected bool IsServer;
///
	this(){
	}
///
	~this(){
	}

///
	void registerClass(char[] class_name, char[][] class_properties){
	}
///
	DogObject addObject(char[] class_name){
		return null;
	}
///
	DogObject[] getObjects(char[] class_name){
		DogObject[] a;
		return a;
	}
///
	DogObject getObject(char[] class_name, uint object_id){
		return null;
	}
///
	void deleteObject(char[] class_name, uint object_id){
	}
///
	void deleteObject(DogObject dog_object){
	}
}

///
public class DogServer : DogBase {
///
	this(){
		IsServer = true;
	}
///
	~this(){
	}

///
	bool create(char[] address, ushort port){
		return true;
	}
///
	uint[] getClients(){
		return [];
	}
///
	void disconnect(uint client_id){
	}
}
bool a(InternetAddress a){
	return true;
}
///
public class DogClient : DogBase {
	private bool IsConnected;

	private bool onConnect(InternetAddress address){
		return true;
	}

	///
	this(){
		IsServer = false;
		IsConnected = false;
	}
	///
	~this(){
	}

	///
	bool connect(char[] address, ushort port){
		return dnet_init(&onConnect, null, null);
		// &&
		//	dnet_client_connect(address, port);
	}
///
	bool isConnected(){
		return true;
	}
///
	uint getClientId(){
		return 0;
	}
///
	void disconnect(){
	}
}




