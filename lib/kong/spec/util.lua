-- Case insensitive lookup function, returns the value and the original key. Or
-- if not found nil and the search key
-- @usage -- sample usage
-- local test = { SoMeKeY = 10 }
-- print(lookup(test, "somekey"))  --> 10, "SoMeKeY"
-- print(lookup(test, "NotFound")) --> nil, "NotFound"
local function lookup(t, k)
  local ok = k
  if type(k) ~= "string" then
    return t[k], k
  else
    k = k:lower()
  end
  for key, value in pairs(t) do
    if tostring(key):lower() == k then
      return value, key
    end
  end
  return nil, ok
end

--- Waits until a specific condition is met.
-- The check function will repeatedly be called (with a fixed interval), until
-- the condition is met, or the
-- timeout value is exceeded.
-- @param f check function that should return `thruthy` when the condition has
-- been met
-- @param timeout maximum time to wait after which an error is thrown
-- @return nothing. It returns when the condition is met, or throws an error
-- when it times out.
-- @usage -- wait 10 seconds for a file "myfilename" to appear
-- helpers.wait_until(function() return file_exist("myfilename") end, 10)
local function wait_until(f, timeout)
  if type(f) ~= "function" then
    error("arg #1 must be a function", 2)
  end

  timeout = timeout or 2
  local tstart = ngx.time()
  local texp, ok = tstart + timeout

  repeat
    ngx.sleep(0.2)
    ok = f()
  until ok or ngx.time() >= texp

  if not ok then
    error("wait_until() timeout", 2)
  end
end

return {
  wait_until = wait_until,
  lookup = lookup
}
