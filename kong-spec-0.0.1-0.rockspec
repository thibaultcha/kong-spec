package = "kong-spec"
version = "0.0.1-0"
source = {
  url = "git://github.com/Mashape/",
  tag = "0.0.1"
}
description = {
  summary = "",
  license = "MIT"
}
dependencies = {
  "busted",
  "penlight",
  "luacheck",
  "luasocket",
  "lua-resty-http",
  "lua-llthreads2"
}
build = {
  type = "builtin",
  modules = {
    ["kong.spec"] = "lib/kong/spec/init.lua",
    ["kong.spec.util"] = "lib/kong/spec/util.lua",
    ["kong.spec.mock-servers"] = "lib/kong/spec/mock-servers.lua",
    ["kong.spec.assertions"] = "lib/kong/spec/assertions.lua",
    ["kong.spec.resty-http-wrapper"] = "lib/kong/spec/resty-http-wrapper.lua"
  }
}
