We will create server, register a class and add a object with a property set.
Then, we will periodically display value for that property.

When client connects, he will change value for that property. 
After that, client wont disconnect, it will stay listening for further changes 
and periodically display value for property.

For each new client you connect, he will change property itself. 
New change will be visible on server and all connected clients.
