-- Modify defaults to have run_plumber = false to run these tests
local rauto = require("rautotest").setup({ use_plumber = false })

local all_same_type = function(table_input, expected_type)
    for _, value in ipairs(table_input) do
        if type(value) ~= expected_type then
            return false
        end
    end
    return true
end

local check_location_contents = function(location)
    assert.are.equal(#location, 8) -- 8 source reference locations
    for _, value in ipairs(location) do
        assert.are.equal(type(value), "number")
    end
end

local check_message_contents = function(message)
    assert.are.equal(#message, 1) -- 1 message to retain for printing
    for _, value in ipairs(message) do
        assert.are.equal(type(value), "string")
    end
end


local check_result_contents = function(results)
    assert.is.True(#results >= 3) -- at least 3 expectations
    assert.is.True(#results <= 4) -- at most 4 expectations
    for _, value in ipairs(results) do
        assert.are.equal(type(value), "string")
        if value == "condition" or value == "expectation" or value == "error" then
            goto continue
        elseif value:match("^expectation") then
            goto continue
        end
        error("Unexpected value in results output: " .. value)
        ::continue::
    end
end

local check_testthat_result
check_testthat_result = function(results_table)
    for key, value in pairs(results_table) do
        if key == "location" then
            check_location_contents(value)
            goto continue
        elseif key == "message" then
            check_message_contents(value)
            goto continue
        elseif key == "result" then
            check_result_contents(value)
            goto continue
        elseif type(value) == "table" then
            check_testthat_result(value)
            goto continue
        end
        error("Unexpected key in results output: key = " .. key .. " and value = " .. vim.inspect(value))
        ::continue::
    end
end

local check_testthat_timing = function(timings_table)
    local expected_length, expected_type
    for key, value in pairs(timings_table) do
        if key == "block" then
            expected_length = 1 -- 1 block
            expected_type = type(value[1]) == "string" and "string" or "userdata"
        elseif key == "nearest_line" then
            expected_length = 1 -- 1 line
            expected_type = "number"
        elseif key == "timing" then
            expected_length = 3 -- 3 times
            expected_type = type(value[1]) == "number" and "number" or "string"-- type(value) == "number" and "number" or "string"
        else
            print(key)
            error("Unexpected key in timings output")
        end
        assert.are.equal(#value, expected_length)
        assert.is.True(all_same_type(value, expected_type))
    end
end

local check_testthat_table = function(table_input)
    for key, value in pairs(table_input) do
        if key == "results" then
            check_testthat_result(value)
        elseif key == "timings" then
            check_testthat_timing(value)
        else
            print(key)
            error("Unexpected key in testthat output")
        end
    end
end

describe("plumber", function()
    it ("can't be killed if it is not running", function()
        if rauto == nil then
            error("couldn't load module")
        end
        -- default load is killed
        local result = rauto.kill_plumber()
        assert.are.equal(0, result)
        -- Returns message that Plumber is not running
        result = rauto.kill_plumber()
        assert.are.equal("Plumber is not running", result)
    end)
    it("can run", function()
        if rauto == nil then
            error("Couldn't load module")
        end
        assert.is.False(rauto.plumber_is_running())
        local plumber_init_result = rauto.run_plumber()
        vim.fn.wait(750, function() end)
        assert.are.same(true, plumber_init_result > 0 and rauto.plumber_pid > 0)
        assert.is.True(rauto.plumber_is_running())
    end)
    it("can print", function()
        local msg_contents = "Foo"
        if rauto == nil then
            error("Couldn't load module")
        end
        local output = rauto.say(msg_contents)
        if output == nil then
            error("output is nil")
        end
        assert.are.same({"The message is: '" .. msg_contents .. "'"}, output.msg)
    end)
    it("will get pid", function()
        local output = rauto.plumber_pid
        assert.are.same(true, output > 0)
    end)
    it("returns testthat output", function()
        if rauto == nil then
            error("Couldn't load module")
        end
        local test_file = "/Users/jrw/rautotest.nvim/tests/testthat/test-basic.R"
        local source_dir = "/Users/jrw/rautotest.nvim/tests/fake-package"
        local testthat_output = rauto.run_testthat(test_file, source_dir)
        -- 2 contexts in the basic test file, First block has 2 tests, second block has 3
        if testthat_output == nil then
            error("testthat_output is nil")
        end
        assert.are.equal(#testthat_output, 2)
        for _, value in pairs(testthat_output) do
            if type(value) == "table" then
                check_testthat_table(value)
            else
                print(vim.inspect(value))
                error("testthat output should be a table of tables")
            end
        end
    end)
    it ("can handle syntax errors in test file", function()
        if rauto == nil then
            error("Couldn't load module")
        end
        local test_file = "/Users/jrw/rautotest.nvim/tests/testthat/test-syntax-error.R"
        local source_dir = "/Users/jrw/rautotest.nvim/tests/fake-package"
        local testthat_output = rauto.run_testthat(test_file, source_dir)
        if testthat_output == nil then
            error("testthat_output is nil")
        end
        assert.are.equal(#testthat_output, 1)
        for _, value in pairs(testthat_output) do
            if type(value) == "table" then
                check_testthat_table(value)
            else
                error("testthat output should be a table of tables")
            end
        end
    end)
    it ("can be killed", function()
        assert.is.True(rauto.plumber_pid > 0)
        local msg_contents = "stopping plumber"
        local output = rauto.say(msg_contents)
        if output == nil then
            error("output is nil")
        end
        assert.are.same({"The message is: '" .. msg_contents .. "'"}, output.msg)

        rauto.kill_plumber()
        assert.are.equal(nil, rauto.plumber_pid)
    end)
end)
