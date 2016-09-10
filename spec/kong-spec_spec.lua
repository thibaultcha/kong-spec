local kong_spec = require "kong.spec"
local cjson = require "cjson"

describe("new()", function()
  it("finds path to kong executable", function()
    local spec = kong_spec.new()
    assert.is_string(spec.bin_path)
  end)
end)

describe("#http_client", function()
  local spec, client

  setup(function()
    spec = kong_spec.new()
  end)
  before_each(function()
    --client = assert(spec.http_client("mockbin.com", 80, 1000))
  end)
  after_each(function()
    --client:close()
  end)

  describe("send()", function()
    it("sends as JSON if Content-Type", function()
      local r = assert(client:send {
        method = "POST",
        path = "/post",
        body = {
          hello = "world",
          foo = {"bar", "baz"}
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.equal(200, r.status)
      local body = assert(r:read_body())
      local json = cjson.decode(body)
      assert.same({
        hello = "world",
        foo = {"bar", "baz"}
      }, json.json)
    end)
    it("sends as www-form-urlencoded if Content-Type", function()
      local r = assert(client:send {
        method = "POST",
        path = "/post",
        body = {
          hello = "world",
          foo = {"bar", "baz"}
        },
        headers = {
          ["Content-Type"] = "application/www-form-urlencoded"
        }
      })
      assert.equal(200, r.status)
      local body = assert(r:read_body())
      local json = cjson.decode(body)
      assert.equal("foo=bar&foo=baz&hello=world", json.data)
    end)
    it("builds querystring", function()
      local r = assert(client:send {
        method = "GET",
        path = "/get",
        query = {
          hello = "world",
          foo = {"bar", "baz"}
        }
      })
      assert.equal(200, r.status)
      local body = assert(r:read_body())
      local json = cjson.decode(body)
      assert.same({
        hello = "world",
        foo = {"bar", "baz"}
      }, json.args)
    end)
  end)
end)

describe("#assertions", function()
  local spec, client

  setup(function()
    spec = kong_spec.new() -- load the assertions
  end)
  before_each(function()
    client = assert(spec.http_client("httpbin.org", 80))
  end)
  after_each(function()
    if client then
      client:close()
    end
  end)

  describe("contains()", function()
    it("verifies list contains value", function()
      local arr = {"one", "three"}
      assert.truthy(assert.contains("one", arr))
      assert.truthy(assert.not_contains("two", arr))
    end)
    it("returns the index of the element found", function()
      local arr = {"one", "three"}
      assert.equals(1, assert.contains("one", arr))
    end)
    it("uses pattenrs if 3rd arg is true", function()
      local arr = {"one", "three"}
      assert.equals(2, assert.contains("ee$", arr, true))
    end)
  end)

  describe("fail()", function()
    it("errors out", function()
      assert.error_matches(function()
        assert.fail()
      end, "fail() assertion called with: (table) { }", nil, true)
    end)
    it("prints args", function()
      assert.error_matches(function()
        assert.fail {hello = "world", foo = "bar"}
      end, [[fail() assertion called with: (table) {
  [1] = {
    [foo] = 'bar'
    [hello] = 'world' } }]], nil, true)
    end)
  end)

  describe("http_client request modifier", function()
    it("fails with bad input", function()
      assert.error(function() assert.request().True(true) end)
      assert.error(function() assert.request(true).True(true) end)
      assert.error(function() assert.request("bad...").True(true) end)
    end)
    it("succeeds with an httpbin request", function()
      local r = assert(client:send {
        method = "GET",
        path = "/get"
      })
      assert.request(r).True(true)
    end)
  end)

  describe("http_client response modifier", function()
    it("fails with bad input", function()
      assert.error(function() assert.response().True(true) end)
      assert.error(function() assert.response(true).True(true) end)
      assert.error(function() assert.response("bad...").True(true) end)
    end)
    it("succeeds with an httpbin response", function()
      local r = assert(client:send {
        method = "GET",
        path = "/get"
      })
      assert.response(r).True(true)
    end)
  end)
end)
