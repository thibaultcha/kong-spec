local conf_loader = require "kong.conf_loader"
local DAOFactory = require "kong.dao.factory"
local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_dir = require "pl.dir"
local http = require "resty.http"
local log = require "kong.cmd.utils.log"

local assertions = require "kong.spec.assertions"
local mock_servers = require "kong.spec.mock-servers"
local resty_http_wrapper_mt = require "kong.spec.resty-http-wrapper"

log.set_lvl(log.levels.quiet)

local _M = {}
_M.__index = _M

function _M.new(conf_path)
  local ok, _, stdout = pl_utils.executeex("which kong")
  if not ok then
    error("could not find 'kong' executable in $PATH")
  end

  local conf = assert(conf_loader(conf_path))
  assertions.build(conf)

  local helper = {
    conf = conf,
    conf_path = conf_path,
    bin_path = stdout,
    dao = DAOFactory(conf)
  }

  return setmetatable(helper, _M)
end

-- @section http_client
--

--- Creates an http client.
-- See https://github.com/pintsized/lua-resty-http
-- @name http_client
-- @param host hostname to connect to
-- @param port port to connect to
-- @param timeout in seconds
-- @return http client
-- @see http_client:send
function _M.http_client(host, port, timeout)
  timeout = timeout or 10000
  local client = assert(http.new())
  client:set_timeout(timeout)
  assert(client:connect(host, port))
  return setmetatable({
    client = client
  }, resty_http_wrapper_mt)
end

function _M:proxy_client(timeout)
  return _M.http_client(self.conf.proxy_ip, self.conf.proxy_port, timeout)
end

function _M:proxy_ssl_client(timeout)
  local client =_M.http_client(self.conf.proxy_ip, self.conf.proxy_ssl_port, timeout)
  client:ssl_handshake()
  return client
end

function _M:admin_client(timeout)
  return _M.http_client(self.conf.admin_ip, self.conf.admin_port, timeout)
end

-- @section shell_helpers
--

function _M.exec(...)
  local ok, _, stdout, stderr = pl_utils.executeex(...)
  if not ok then
    stdout = nil -- don't return 3rd value if fail because of busted's `assert`
  end
  return ok, stderr, stdout
end

function _M:kong_exec(cmd, env)
  cmd = cmd or ""
  env = env or {}

  local env_vars = ""
  for k, v in pairs(env) do
    env_vars = string.format("%s KONG_%s='%s'", env_vars, k:upper(), v)
  end

  return _M.exec(env_vars.." "..self.bin_path.." "..cmd)
end

function _M:prepare_prefix(prefix)
  prefix = prefix or self.conf.prefix
  _M.exec("rm -rf "..prefix.."/*")
  return pl_dir.makepath(prefix)
end

function _M:clean_prefix(prefix)
  prefix = prefix or self.conf.prefix
  if pl_path.exists(prefix) then
    return pl_dir.rmtree(prefix)
  end
  return true
end

-- @section test_instance
--

function _M:start_kong(env)
  env = env or {}
  local ok, err = _M.prepare_prefix(env.prefix)
  if not ok then return nil, err end

  return _M.kong_exec("start --conf "..self.conf_path, env)
end

function _M:stop_kong(prefix, preserve_prefix)
  prefix = prefix or self.conf.prefix
  local ok, err = _M.kong_exec("stop --prefix "..prefix)
  self.dao:truncate_tables()
  if not preserve_prefix then
    _M.clean_prefix(prefix)
  end
  return ok, err
end

function _M:kill_all(prefix)
  local kill = require "kong.cmd.utils.kill"

  self.dao:truncate_tables()

  local default_conf = conf_loader(nil, {prefix = prefix or self.conf.prefix})
  local running_conf = conf_loader(default_conf.kong_conf)
  if not running_conf then return end

  -- kill kong_tests.conf services
  for _, pid_path in ipairs {running_conf.nginx_pid,
                             running_conf.dnsmasq_pid,
                             running_conf.serf_pid} do
    if pl_path.exists(pid_path) then
      kill.kill(pid_path, "-TERM")
    end
  end
end

-- @section penlight
--

_M.dir = pl_dir
_M.path = pl_path
_M.file = pl_file
_M.utils = pl_utils

-- @section mock_servers
--

for k, v in pairs(mock_servers) do
  _M[k] = v
end

return _M
