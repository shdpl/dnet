/**
*/
module dogslow;

private import dnet;


///
class DogObject {
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

///
public class DogClient : DogBase {
///
	bool connect(char[] address, ushort port){
		return true;
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




