bud examples\dnet_stress\client.d -I.\src\dogslow;.\src\dnet -clean -Ddapi -unittest
bud examples\dnet_stress\server.d -I.\src\dogslow;.\src\dnet -clean -Ddapi -unittest

bud examples\dnet_correct\client.d -I.\src\dogslow;.\src\dnet -clean -Ddapi -unittest
bud examples\dnet_correct\server.d -I.\src\dogslow;.\src\dnet -clean -Ddapi -unittest

bud examples\dogslow_correct\client.d -I.\src\dogslow;.\src\dnet -clean -Ddapi -unittest
bud examples\dogslow_correct\server.d -I.\src\dogslow;.\src\dnet -clean -Ddapi -unittest