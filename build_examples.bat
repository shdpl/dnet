SET DMD=dmd -debug
SET INC=src/dnet.d src/dogslow.d

%DMD% -ofbin\dnet_hello_world_server.exe examples/dnet/hello_world/server.d %INC% 
%DMD% -ofbin\dnet_hello_world_client.exe examples/dnet/hello_world/client.d %INC%

del *.map
del *.obj
