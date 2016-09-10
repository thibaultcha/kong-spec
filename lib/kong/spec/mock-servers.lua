-- TCP/UDP mock server helpers

local threads = require "llthreads2.ex"
local socket = require "socket"

--- Starts a TCP server.
-- Accepts a single connection and then closes, echoing what was received
-- (single read).
-- @name tcp_server
-- @param `port`    The port where the server will be listening to
-- @return `thread` A thread object
local function tcp_server(port, ...)
  local thread = threads.new({
    function(_port)
      local server = assert(socket.tcp())
      server:settimeout(10)
      assert(server:setoption('reuseaddr', true))
      assert(server:bind("*", _port))
      assert(server:listen())
      local client = server:accept()
      local line, err = client:receive()
      if not err then client:send(line .. "\n") end
      client:close()
      server:close()
      return line
    end
  }, port)

  return thread:start(...)
end

--- Starts a HTTP server.
-- Accepts a single connection and then closes. Sends a 200 ok, 'Connection:
-- close' response.
-- If the request received has path `/delay` then the response will be delayed
-- by 2 seconds.
-- @name http_server
-- @param `port`    The port where the server will be listening to
-- @return `thread` A thread object
local function http_server(port, ...)
  local thread = threads.new({
    function(_port)
      local server = assert(socket.tcp())
      assert(server:setoption('reuseaddr', true))
      assert(server:bind("*", _port))
      assert(server:listen())
      local client = server:accept()

      local lines = {}
      local line, err
      while #lines < 7 do
        line, err = client:receive()
        if err then
          break
        else
          table.insert(lines, line)
        end
      end

      if #lines > 0 and lines[1] == "GET /delay HTTP/1.0" then
        ngx.sleep(2)
      end

      if err then
        server:close()
        error(err)
      end

      client:send("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
      client:close()
      server:close()
      return lines
    end
  }, port)

  return thread:start(...)
end

--- Starts a UDP server.
-- Accepts a single connection, reading once and then closes
-- @name udp_server
-- @param `port`    The port where the server will be listening to
-- @return `thread` A thread object
local function udp_server(port)
  local thread = threads.new({
    function(_port)
      local server = assert(socket.udp())
      server:settimeout(10)
      server:setoption("reuseaddr", true)
      server:setsockname("127.0.0.1", _port)
      local data = server:receive()
      server:close()
      return data
    end
  }, port or 9999)

  thread:start()

  ngx.sleep(0.1)

  return thread
end

return {
  tcp_server = tcp_server,
  http_server = http_server,
  udp_server = udp_server
}
