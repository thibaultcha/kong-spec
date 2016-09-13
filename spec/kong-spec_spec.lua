local kong_spec = require "kong.spec"
local cjson = require "cjson"

describe("kong_spec", function()
  it("attaches useful penlight modules", function()
    assert.truthy(kong_spec.dir)
    assert.truthy(kong_spec.path)
    assert.truthy(kong_spec.file)
    assert.truthy(kong_spec.utils)
  end)

  describe("new()", function()
    it("finds path to kong executable", function()
      local spec = kong_spec.new()
      assert.is_string(spec.bin_path)
    end)
  end)
end)

describe("#http_client", function()
  local spec, client

  setup(function()
    spec = kong_spec.new()
  end)
  before_each(function()
    client = assert(spec.http_client("httpbin.org", 80, 1000))
  end)
  after_each(function()
    client:close()
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
  local spec
  local httpbin_client
  -- local mockbin_client -- disabled until ipv6 removal

  setup(function()
    spec = kong_spec.new() -- load the assertions
  end)
  before_each(function()
    httpbin_client = assert(spec.http_client("httpbin.org", 80))
    --mockbin_client = assert(spec.http_client("mockbin.com", 80))
  end)
  after_each(function()
    if httpbin_client then httpbin_client:close() end
    --if mockbin_client then mockbin_client:close() end
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
      local r = assert(httpbin_client:send {
        method = "GET",
        path = "/get"
      })
      assert.request(r).True(true)
    end)
    pending("succeeds with a mockbin request", function()
      local r = assert(mockbin_client:send {
        method = "GET",
        path = "/request"
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
      local r = assert(httpbin_client:send {
        method = "GET",
        path = "/get"
      })
      assert.response(r).True(true)
    end)
    pending("succeeds with a mockbin response", function()
      local r = assert(mockbin_client:send {
        method = "GET",
        path = "/request"
      })
      assert.response(r).True(true)
    end)
    it("fails with a non httpbin/mockbin response", function()
      local r = assert(httpbin_client:send {
        method = "GET",
        path = "/abcd" -- path not supported, but yields valid response for test
      })
      assert.error(function() assert.request(r).True(true) end)
    end)
  end)

  describe("http_client status code assertion", function()
    it("validates against a resty-http response table", function()
      assert.has_no_error(function()
        assert.res_status(200, {status = 200, read_body = function()
          return ""
        end})
      end)
    end)
    it("refuses table if not a resty-http response", function()
      assert.error_matches(function()
        assert.res_status(200, {status = 200})
      end, "Expected a http_client response.", nil, true)

      assert.error_matches(function()
        assert.res_status("200", {status = 200})
      end, "Expected response code must be a number value.", nil, true)
    end)
    it("returns stripped body", function()
      assert.has_no_error(function()
        local body = assert.res_status(200, {status = 200, read_body = function()
          return "\n a body   "
        end})

        assert.equal(body, "a body")
      end)
    end)
  end)

  describe("http_client jsonbody assertion", function()
    it("fails with explicit or no parameters", function()
      assert.error(function() assert.jsonbody({}) end)
      assert.error(function() assert.jsonbody() end)
    end)
    pending("succeeds on a mockbin response", function()
      local r = assert(mockbin_client:send {
        method = "GET",
        path = "/request"
      })
      local json = assert.response(r).has.jsonbody()
      assert(json.url:find("mockbin%.com"), "expected a mockbin response")
    end)
    pending("succeeds on a mockbin request", function()
      local r = assert(mockbin_client:send {
        method = "GET",
        path = "/request",
        body = {hello = "world"},
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local json = assert.request(r).has.jsonbody()
      assert.equals("world", json.hello)
    end)
    it("fails on an httpbin request", function()
      local r = assert(httpbin_client:send {
        method = "POST",
        path = "/post",
        body = {hello = "world"},
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.error(function() assert.request(r).has.jsonbody() end)
    end)
  end)

  describe("header assertion", function()
    pending("checks appropriate response headers", function()
      local r = assert(mockbin_client:send {
        method = "GET",
        path = "/request",
        body = { hello = "world" },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local v1 = assert.response(r).has.header("x-powered-by")
      local v2 = assert.response(r).has.header("X-POWERED-BY")
      assert.equals(v1, v2)
      assert.error(function() assert.response(r).has.header("does not exists") end)
    end)
    pending("checks appropriate mockbin request headers", function()
      local r = assert(mockbin_client:send {
        method = "GET",
        path = "/request",
        headers = {
          ["just-a-test-header"] = "just-a-test-value"
        }
      })
      local v1 = assert.request(r).has.header("just-a-test-header")
      local v2 = assert.request(r).has.header("just-a-test-HEADER")
      assert.equals("just-a-test-value", v1)
      assert.equals(v1, v2)
      assert.error(function() assert.response(r).has.header("does not exists") end)
    end)
    it("checks appropriate httpbin request headers", function()
      local r = assert(httpbin_client:send {
        method = "GET",
        path = "/get",
        headers = {
          ["just-a-test-header"] = "just-a-test-value"
        }
      })
      local v1 = assert.request(r).has.header("just-a-test-header")
      local v2 = assert.request(r).has.header("just-a-test-HEADER")
      assert.equals("just-a-test-value", v1)
      assert.equals(v1, v2)
      assert.error(function() assert.response(r).has.header("does not exists") end)
    end)
  end)

  describe("queryParam assertion", function()
    pending("checks appropriate mockbin query parameters", function()
      local r = assert(mockbin_client:send {
        method = "GET",
        path = "/request",
        query = {
          hello = "world"
        }
      })
      local v1 = assert.request(r).has.queryparam("hello")
      local v2 = assert.request(r).has.queryparam("HELLO")
      assert.equals("world", v1)
      assert.equals(v1, v2)
      assert.error(function() assert.response(r).has.queryparam("notHere") end)
    end)
    it("checks appropriate httpbin query parameters", function()
      local r = assert(httpbin_client:send {
        method = "POST",
        path = "/post",
        query = {
          hello = "world"
        },
        body = {
          hello2 = "world2"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      local v1 = assert.request(r).has.queryparam("hello")
      local v2 = assert.request(r).has.queryparam("HELLO")
      assert.equals("world", v1)
      assert.equals(v1, v2)
      assert.error(function() assert.response(r).has.queryparam("notHere") end)
    end)
  end)

  describe("formparam assertion", function()
    pending("checks appropriate mockbin url-encoded form parameters", function()
      local r = assert(mockbin_client:send {
        method = "POST",
        path = "/request",
        body = {
          hello = "world"
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded"
        }
      })
      local v1 = assert.request(r).has.formparam("hello")
      local v2 = assert.request(r).has.formparam("HELLO")
      assert.equals("world", v1)
      assert.equals(v1, v2)
      assert.error(function() assert.request(r).has.queryparam("notHere") end)
    end)
    pending("fails with mockbin non-url-encoded form data", function()
      local r = assert(mockbin_client:send {
        method = "POST",
        path = "/request",
        body = {
          hello = "world"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.error(function() assert.request(r).has.formparam("hello") end)
    end)
    it("checks appropriate httpbin url-encoded form parameters", function()
      local r = assert(httpbin_client:send {
        method = "POST",
        path = "/post",
        body = {
          hello = "world"
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded"
        }
      })
      local v1 = assert.request(r).has.formparam("hello")
      local v2 = assert.request(r).has.formparam("HELLO")
      assert.equals("world", v1)
      assert.equals(v1, v2)
      assert.error(function() assert.request(r).has.queryparam("notHere") end)
    end)
    it("fails with httpbin non-url-encoded form parameters", function()
      local r = assert(httpbin_client:send {
        method = "POST",
        path = "/post",
        body = {
          hello = "world"
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      assert.error(function() assert.request(r).has.formparam("hello") end)
    end)
  end)
end)

describe("#shell", function()
  local spec = kong_spec.new()
  local pl_dir = require "pl.dir"
  local pl_file = require "pl.file"
  local pl_path = require "pl.path"

  math.randomseed(os.time())

  describe("exec()", function()
    it("wraps executeex()", function()
      local ok, stderr, stdout = spec.exec([[echo "hello world"]])
      assert.equal("", stderr)
      assert.equal("hello world\n", stdout)
      assert.True(ok)
    end)
    it("removes return value 3 if command fails", function()
      -- this is to avoid busted's `assert()` to error out since
      -- it overrides Lua's `assert` and expects arg #3 to be a
      -- number, and nothing else.
      local ok, stderr, stdout = spec.exec([[blah]])
      assert.equal("sh: blah: command not found\n", stderr)
      assert.is_nil(stdout)
      assert.False(ok)
    end)
  end)

  describe("prepare_prefix()", function()
    it("creates directory", function()
      local tmp = pl_path.join("/tmp", "prefix_"..math.random(1, 100))

      finally(function()
        pcall(pl_dir.rmtree, tmp)
      end)

      assert(spec:prepare_prefix(tmp))
      assert(pl_path.exists(tmp))
    end)
    it("empties directory if already contains files", function()
      local tmp = pl_path.join("/tmp", "prefix_"..math.random(1, 100))
      local tmp_file = pl_path.join(tmp, "test_file.txt")

      finally(function()
        pcall(pl_dir.rmtree, tmp)
      end)

      assert(pl_dir.makepath(tmp))
      assert(pl_file.write(tmp_file, ""))
      assert(pl_path.exists(tmp_file))

      assert(spec:prepare_prefix(tmp))
      assert.False(pl_path.exists(tmp_file))
    end)
  end)

  describe("clean_prefix()", function()
    it("ignores if directory does not exist", function()
      local tmp = pl_path.join("/tmp", "prefix_"..math.random(1, 100))

      assert.has_no_error(function()
        assert(spec:clean_prefix(tmp))
      end)
    end)
    it("removes directory if exists", function()
      local tmp = pl_path.join("/tmp", "prefix_"..math.random(1, 100))

      finally(function()
        pcall(pl_dir.rmtree, tmp)
      end)

      assert(pl_dir.makepath(tmp))
      assert(spec:clean_prefix(tmp))
      assert.False(pl_path.exists(tmp))
    end)
  end)

  pending("kong_exec()", function()

  end)
end)

pending("#mock_servers", function()

end)
