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
    ["kong.spec"] = "src/kong/spec/init.lua",
    ["kong.spec.util"] = "src/kong/spec/util.lua",
    ["kong.spec.mock-servers"] = "src/kong/spec/mock-servers.lua",
    ["kong.spec.assertions"] = "src/kong/spec/assertions.lua",
    ["kong.spec.resty-http-wrapper"] = "src/kong/spec/resty-http-wrapper.lua"
  }
}
