--- A wrapper around lua-resty-http

local kong_util = require "kong.tools.utils"
local cjson = require "cjson"
local util = require "kong.spec.util"
local find = string.find

local resty_http_wrapper_mt = {}

function resty_http_wrapper_mt:__index(k)
  local f = rawget(resty_http_wrapper_mt, k)
  if f then
    return f
  end

  return self.client[k]
end

-- Wrapper around `:request()`with some added content-type
-- functionnalities.
-- If `opts.body` is a table and "Content-Type" header contains
-- `application/json`, `www-form-urlencoded`, or `multipart/form-data`, then it
-- will automatically encode the body according to the content type.
-- If `opts.query` is a table, a query string will be constructed from it and
-- appended to the request path (assuming none is already present).
-- @name http_client:send
-- @param opts table with options. See https://github.com/pintsized/lua-resty-http
function resty_http_wrapper_mt:send(opts)
  opts = opts or {}

  -- build body
  local headers = opts.headers or {}
  local content_type, content_type_name = util.lookup(headers, "Content-Type")
  content_type = content_type or ""
  local t_body_table = type(opts.body) == "table"
  if find(content_type, "application/json", nil, true) and t_body_table then
    opts.body = cjson.encode(opts.body)
  elseif find(content_type, "www-form-urlencoded", nil, true) and t_body_table then
    opts.body = kong_util.encode_args(opts.body, true) -- true: not % encoded
  elseif find(content_type, "multipart/form-data", nil, true) and t_body_table then
    local form = opts.body
    local boundary = "8fd84e9444e3946c"
    local body = ""

    for k, v in pairs(form) do
      body = body.."--"..boundary.."\r\nContent-Disposition: form-data; name=\""..
             k.."\"\r\n\r\n"..tostring(v).."\r\n"
    end

    if body ~= "" then
      body = body.."--"..boundary.."--\r\n"
    end

    local clength = util.lookup(headers, "content-length")
    if not clength then
      headers["content-length"] = #body
    end

    if not content_type:find("boundary=") then
      headers[content_type_name] = content_type.."; boundary="..boundary
    end

    opts.body = body
  end

  -- build querystring (assumes none is currently in 'opts.path')
  if type(opts.query) == "table" then
    local qs = kong_util.encode_args(opts.query)
    opts.path = opts.path.."?"..qs
    opts.query = nil
  end

  local res, err = self:request(opts)
  if res then
    -- wrap the read_body() so it caches the result and can be called multiple
    -- times
    local reader = res.read_body
    res.read_body = function(_self)
      if not _self._cached_body and not _self._cached_error then
        _self._cached_body, _self._cached_error = reader(self)
      end
      return _self._cached_body, _self._cached_error
    end
  end

  return res, err
end

return resty_http_wrapper_mt

