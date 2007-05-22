bud tests\dnet_stress\client.d -Isrc -clean -Ddapi -unittest
bud tests\dnet_stress\server.d -Isrc -clean -Ddapi -unittest

bud tests\dnet_correct\client.d -Isrc -clean -Ddapi -unittest
bud tests\dnet_correct\server.d -Isrc -clean -Ddapi -unittest

bud tests\dogslow_correct\client.d -Isrc -clean -Ddapi -unittest
bud tests\dogslow_correct\server.d -Isrc -clean -Ddapi -unittest