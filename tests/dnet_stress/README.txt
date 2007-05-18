This example should test max number of packets & bytes 
that server can recieve and send back to connected clients.
Basically, clients are flooding server and server is sending back.

It is rather interesting to see difference in performance between reliable & unreliable sending mode 
(change RELIABLE bool value in files).
I expect everlasting optimization here 
so don't be discouradged if packet count per sec is small at the moment.


