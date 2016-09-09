local kong_spec = require "kong.spec"

describe("new()", function()
  it("finds path to kong executable", function()
    local spec = kong_spec.new()
    assert.is_string(spec.bin_path)
  end)

  describe("assertions", function()
    setup(function()
      kong_spec.new() -- load the assertions
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
  end)
end)
