--------------------
-- Custom assertions

local say = require "say"
local util = require "kong.spec.util"
local cjson = require "cjson"
local pl_file = require "pl.file"
local luassert = require "luassert.assert"
local pl_stringx = require "pl.stringx"

-- wrap assert and create a new kong-assert state table for each call
local old_assert = assert
local kong_state
-- luacheck: globals assert
assert = function(...)
  kong_state = {}
  return old_assert(...)
end

-- tricky part: the assertions below, should not reset the `kong_state`
-- inserted above. Hence we shadow the global assert (patched one) with a local
-- assert (unpatched) to prevent this.
local assert = old_assert


local function build_assertions(conf)
  --- Generic modifier "response".
  -- Will set a "response" value in the assertion state, so following
  -- assertions will operate on the value set.
  -- @name response
  -- @param response results from `http_client:send` function.
  -- @usage
  -- local res = assert(client:send { ..your request parameters here ..})
  -- local length = assert.response(res).has.header("Content-Length")
  local function modifier_response(state, arguments)
    assert(arguments.n > 0,
          "response modifier requires a response object as argument")

    local res = arguments[1]

    assert(type(res) == "table" and type(res.read_body) == "function",
           "response modifier requires a response object as argument, got: "..tostring(res))

    kong_state.kong_response = res
    kong_state.kong_request = nil

    return state
  end
  luassert:register("modifier", "response", modifier_response)

  --- Generic modifier "request".
  -- Will set a "request" value in the assertion state, so following
  -- assertions will operate on the value set.
  -- The request must be inside a 'response' from mockbin.org or httpbin.org
  -- @name request
  -- @param response results from `http_client:send` function. The request will
  -- be extracted from the response.
  -- @usage
  -- local res = assert(client:send { ..your request parameters here ..})
  -- local length = assert.request(res).has.header("Content-Length")
  local function modifier_request(state, arguments)
    local generic = "The assertion 'request' modifier takes a http response"
                  .." object as input to decode the json-body returned by"
                  .." httpbin.org/mockbin.org, to retrieve the proxied request."

    local res = arguments[1]

    assert(type(res) == "table" and type(res.read_body) == "function",
           "Expected a http response object, got '"..tostring(res).."'. "..generic)

    local body, err
    body = assert(res:read_body())
    body, err = cjson.decode(body)

    assert(body, "Expected the http response object to have a json encoded body,"
               .." but decoding gave error '"..tostring(err).."'. "..generic)

    -- check if it is a mockbin request
    if util.lookup((res.headers or {}),"X-Powered-By") ~= "mockbin" then
      -- not mockbin, so httpbin?
      assert(type(body.url) == "string" and body.url:find("//httpbin.org", 1, true),
             "Could not determine the response to be from either mockbin.com or httpbin.org")
    end

    kong_state.kong_request = body
    kong_state.kong_response = nil

    return state
  end
  luassert:register("modifier", "request", modifier_request)

  --- Generic fail assertion. A convenience function for debugging tests, always
  -- fails. It will output the values it was called with as a table, with an `n`
  -- field to indicate the number of arguments received.
  -- @name fail
  -- @param ... any set of parameters to be displayed with the failure
  -- @usage
  -- assert.fail(some, value)
  local function fail(state, args)
    local out = {}
    for k,v in pairs(args) do out[k] = v end
    out.n = nil
    args[1] = out
    args.n = 1
    return false
  end
  say:set("assertion.fail.negative", [[
fail() assertion called with: %s]])
  luassert:register("assertion", "fail", fail,
                    "assertion.fail.negative",
                    "assertion.fail.negative")

  --- Assertion to check whether a value lives in an array.
  -- @name contains
  -- @param expected The value to search for
  -- @param array The array to search for the value
  -- @param pattern (optional) If thruthy, then `expected` is matched as a string
  -- pattern
  -- @return the index at which the value was found
  -- @usage
  -- local arr = { "one", "three" }
  -- local i = assert.contains("one", arr)        --> passes; i == 1
  -- local i = assert.contains("two", arr)        --> fails
  -- local i = assert.contains("ee$", arr, true)  --> passes; i == 2
  local function contains(state, args)
    local expected, arr, pattern = unpack(args)
    local found
    for i = 1, #arr do
      if pattern and string.match(arr[i], expected) or arr[i] == expected then
        found = i
        break
      end
    end
    return found ~= nil, found and {found} or nil
  end
  say:set("assertion.contains.negative", [[
Expected array to contain element.
Expected to contain:
%s]])
  say:set("assertion.contains.positive", [[
Expected array to not contain element.
Expected to not contain:
%s]])
  luassert:register("assertion", "contains", contains,
                    "assertion.contains.negative",
                    "assertion.contains.positive")

  --- Assertion to check the statuscode of a http response.
  -- @name status
  -- @param expected the expected status code
  -- @param response (optional) results from `http_client:send` function,
  -- alternatively use `response`.
  -- @return the response body as a string
  -- @usage
  -- local res = assert(client:send { .. your request params here .. })
  -- local body = assert.has.status(200, res)             -- or alternativly
  -- local body = assert.response(res).has.status(200)    -- does the same
  local function res_status(state, args)
    assert(not kong_state.kong_request,
           "Cannot check statuscode against a request object,"
         .." only against a response object")

    local expected = args[1]
    local res = args[2] or kong_state.kong_response

    assert(type(expected) == "number",
           "Expected response code must be a number value. Got: "..tostring(expected))
    assert(type(res) == "table" and type(res.read_body) == "function",
           "Expected a http_client response. Got: "..tostring(res))

    if expected ~= res.status then
      local body, err = res:read_body()
      if not body then body = "Error reading body: "..err end
      table.insert(args, 1, pl_stringx.strip(body))
      table.insert(args, 1, res.status)
      table.insert(args, 1, expected)
      args.n = 3

      if res.status == 500 then
        -- on HTTP 500, we can try to read the server's error logs
        -- for debugging purposes (very useful for travis)
        local str = pl_file.read(conf.nginx_err_logs)
        if not str then
          return false -- no err logs to read in this prefix
        end

        local str_t = pl_stringx.splitlines(str)
        local first_line = #str_t - math.min(60, #str_t) + 1
        local msg_t = {"\nError logs ("..conf.nginx_err_logs.."):"}
        for i = first_line, #str_t do
          msg_t[#msg_t+1] = str_t[i]
        end

        table.insert(args, 4, table.concat(msg_t, "\n"))
        args.n = 4
      end

      return false
    else
      local body, err = res:read_body()
      local output = body
      if not output and err then
        output = "Error reading body: "..err
      end
      output = pl_stringx.strip(output)
      table.insert(args, 1, output)
      table.insert(args, 1, res.status)
      table.insert(args, 1, expected)
      args.n = 3
      return true, {pl_stringx.strip(body)}
    end
  end
  say:set("assertion.res_status.negative", [[
Invalid response status code.
Status expected:
%s
Status received:
%s
Body:
%s
%s]])
  say:set("assertion.res_status.positive", [[
Invalid response status code.
Status not expected:
%s
Status received:
%s
Body:
%s
%s]])
  luassert:register("assertion", "status", res_status,
                    "assertion.res_status.negative", "assertion.res_status.positive")
  luassert:register("assertion", "res_status", res_status,
                    "assertion.res_status.negative", "assertion.res_status.positive")

  --- Checks and returns a json body of an http response/request. Only checks
  -- validity of the json, does not check appropriate headers. Setting the target
  -- to check can be done through `request` or `response` (requests are only
  -- supported with mockbin.com).
  -- @name jsonbody
  -- @return the decoded json as a table
  -- @usage
  -- local res = assert(client:send { .. your request params here .. })
  -- local json_table = assert.response(res).has.jsonbody()
  local function jsonbody(state, args)
    assert(args[1] == nil and kong_state.kong_request or kong_state.kong_response,
           "the `jsonbody` assertion does not take parameters. "..
           "Use the `response`/`require` modifiers to set the target to operate on")

    if kong_state.kong_response then
      local body = kong_state.kong_response:read_body()
      local json, err = cjson.decode(body)
      if not json then
        table.insert(args, 1, "Error decoding: "..tostring(err).."\nResponse body:"..body)
        args.n = 1
        return false
      end
      return true, {json}
    else
      assert(kong_state.kong_request.postData, "No post data found in the request. Only mockbin.com is supported!")
      local json, err = cjson.decode(kong_state.kong_request.postData.text)
      if not json then
        table.insert(args, 1, "Error decoding: "..tostring(err).."\nRequest body:"..kong_state.kong_request.postData.text)
        args.n = 1
        return false
      end
      return true, {json}
    end
  end
  say:set("assertion.jsonbody.negative", [[
Expected response body to contain valid json. Got:
%s]])
  say:set("assertion.jsonbody.positive", [[
Expected response body to not contain valid json. Got:
%s]])
  luassert:register("assertion", "jsonbody", jsonbody,
                    "assertion.jsonbody.negative",
                    "assertion.jsonbody.positive")

  --- Adds an assertion to look for a named header in a `headers` subtable.
  -- Header name comparison is done case-insensitive.
  -- @name header
  -- @param name header name to look for (case insensitive).
  -- @see response
  -- @see request
  -- @return value of the header
  local function res_header(state, args)
    local header = args[1]
    local res = args[2] or kong_state.kong_request or kong_state.kong_response
    assert(type(res) == "table" and type(res.headers) == "table",
           "'header' assertion input does not contain a 'headers' subtable")
    local value = util.lookup(res.headers, header)
    table.insert(args, 1, res.headers)
    table.insert(args, 1, header)
    args.n = 2
    if not value then
      return false
    end
    return true, {value}
  end
  say:set("assertion.res_header.negative", [[
Expected header:
%s
But it was not found in:
%s]])
  say:set("assertion.res_header.positive", [[
Did not expected header:
%s
But it was found in:
%s]])
  luassert:register("assertion", "header", res_header,
                    "assertion.res_header.negative",
                    "assertion.res_header.positive")

  ---
  -- An assertion to look for a query parameter in a `queryString` subtable.
  -- Parameter name comparison is done case-insensitive.
  -- @name queryparam
  -- @param name name of the query parameter to look up (case insensitive)
  -- @return value of the parameter
  local function req_query_param(state, args)
    local param = args[1]
    local req = kong_state.kong_request
    assert(req, "'queryparam' assertion only works with a request object")
    local params
    if type(req.queryString) == "table" then
      -- it's a mockbin one
      params = req.queryString
    elseif type(req.args) == "table" then
      -- it's a httpbin one
      params = req.args
    else
      error("No query parameters found in request object")
    end
    local value = util.lookup(params, param)
    table.insert(args, 1, params)
    table.insert(args, 1, param)
    args.n = 2
    if not value then
      return false
    end
    return true, {value}
  end
  say:set("assertion.req_query_param.negative", [[
Expected query parameter:
%s
But it was not found in:
%s]])
  say:set("assertion.req_query_param.positive", [[
Did not expected query parameter:
%s
But it was found in:
%s]])
  luassert:register("assertion", "queryparam", req_query_param,
                    "assertion.req_query_param.negative",
                    "assertion.req_query_param.positive")

  ---
  -- Adds an assertion to look for a urlencoded form parameter in a mockbin request.
  -- Parameter name comparison is done case-insensitive. Use the `request` modifier to set
  -- the request to operate on.
  -- @name formparam
  -- @param name name of the form parameter to look up (case insensitive)
  -- @return value of the parameter
  local function req_form_param(state, args)
    local param = args[1]
    local req = kong_state.kong_request
    assert(req, "'formparam' assertion can only be used with a mockbin/httpbin request object")

    local value
    if req.postData then
      -- mockbin request
      value = util.lookup((req.postData or {}).params, param)
    elseif (type(req.url) == "string") and (req.url:find("//httpbin.org", 1, true)) then
      -- hhtpbin request
      value = util.lookup(req.form or {}, param)
    else
      error("Could not determine the request to be from either mockbin.com or httpbin.org")
    end
    table.insert(args, 1, req)
    table.insert(args, 1, param)
    args.n = 2
    if not value then
      return false
    end
    return true, {value}
  end
  say:set("assertion.req_form_param.negative", [[
Expected url encoded form parameter:
%s
But it was not found in request:
%s]])
  say:set("assertion.req_form_param.positive", [[
Did not expected url encoded form parameter:
%s
But it was found in request:
%s]])
  luassert:register("assertion", "formparam", req_form_param,
                    "assertion.req_form_param.negative",
                    "assertion.req_form_param.positive")
end

return {
  build = build_assertions
}
