local M = {}

-- Async curl request helper with JSON support
local function async_curl(url, opts)
    opts = opts or {}
    local args = { "curl", "-s", url }

    -- Method (default: POST)
    if opts.method then
        table.insert(args, "-X")
        table.insert(args, opts.method)
    end

    -- Headers
    if opts.headers then
        for k, v in pairs(opts.headers) do
            table.insert(args, "-H")
            table.insert(args, string.format("%s: %s", k, v))
        end
    end

    -- Body (Lua table to JSON by default)
    if opts.body then
        local body = opts.body
        if type(body) == "table" then
            body = vim.json.encode(body)
            -- add JSON header if not set already
            local has_content_type = false
            if opts.headers then
                for k, _ in pairs(opts.headers) do
                    if k:lower() == "content-type" then
                        has_content_type = true
                        break
                    end
                end
            end
            if not has_content_type then
                table.insert(args, "-H")
                table.insert(args, "Content-Type: application/json")
            end
        end
        table.insert(args, "-d")
        table.insert(args, body)
    end
 
    vim.fn.jobstart(args, {
        stdout_buffered = true,
        on_stdout = function(_, data, _)
            if not data or #data == 0 then return end
            local output = table.concat(data, "\n")

            local ok, decoded = pcall(vim.json.decode, output)
            if opts.on_success then
                if ok then
                    opts.on_success(decoded, output)
                else
                    opts.on_success(nil, output)
                end
            end
        end,
        on_stderr = function(_, data, _)
            if data and #data > 0 then
                local err = table.concat(data, "\n")
                if opts.on_error then
                    opts.on_error(err)
                else
                    vim.notify(err, vim.log.levels.ERROR)
                end
            end
        end,
        on_exit = function(_, code, _)
            if opts.on_exit then
                opts.on_exit(code)
            end
        end,
    })
end

M.defaults = {
    source_dir = "R",
    test_dir = "tests/testthat",
    namespace = "rautotest",
    plumber_port = 8000,
    outcome_icons = {
        expectation_success = "✅",
        expectation_warning = "⚠️",
        expectation_failure = "❌",
        expectation_error = "⁉️",
        expectation_skip = "⏭️",
        timing = "⏱️",
    },
    outcome_message = {
        expectation_warning = "Warning: ",
        expectation_failure = "Failure: ",
        expectation_error = "⁉️ Syntax error ⁉️",
    }
}

M.options = {}

function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
    if M.options.namespace ~= nil then
        M.namespace = vim.api.nvim_create_namespace(M.options.namespace)
    end
    M.run_plumber()
    return M
end

-- https://stackoverflow.com/questions/52417903/how-to-get-the-current-directory-of-the-running-lua-script
local function is_win()
    return package.config:sub(1, 1) == '\\'
end

local function get_path_separator()
    if is_win() then
        return '\\'
    end
    return '/'
end

local function resolve_path()
    local str = debug.getinfo(2, 'S').source:sub(2)
    if is_win() then
        str = str:gsub('/', '\\')
    end
    return str:match('(.*' .. get_path_separator() .. ')')
end

--- Takes a path and constructs a plumber url based off the plumber port
--- @param path string The path to append to the url
local construct_plumber_url = function(path)
    return M.plumber_url .. "/" .. path
end


--- Function to decode the json result and throw an error if the curl call failed
--- @param curl_result table The result of the curl call
local decode_curl_result = function(curl_result)
    if curl_result == nil or curl_result.status ~= 200 or curl_result.body == nil then
        error("curl failed: " .. vim.inspect(curl_result))
    end
    return vim.fn.json_decode(curl_result.body);
end

M.plumber_is_running = function()
    return M.job_id ~= nil and M.job_id > 0
end

M.run_plumber = function()
    if M.plumber_is_running() then
        print("Plumber is already running")
        return
    end
    local current_path = resolve_path()
    local src_file = vim.fn.fnamemodify(current_path, ':p:h') .. get_path_separator() .. 'plumbr.R'
    local r_args = string.format([[plumber::pr_run(plumber::pr('%s'), port = %d)]], src_file, M.options.plumber_port)
    local plumber_args = { 'Rscript', '-e', r_args }
    M.job_id = vim.fn.jobstart(plumber_args, {
        on_stdout = function(_, data, _)
            print(vim.inspect(data))
        end,
        on_stderr = function(_, data, _)
            print(vim.inspect(data))
        end,
        on_exit = function(_, _, _)
            print("Plumber exited")
        end,
        stdout_buffered = true,
        stderr_buffered = true,
        detach = false,
    })
    M.plumber_url = string.format([[http://localhost:%d]], M.options.plumber_port)
    -- Tidy up the job when Neovim exits
    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            if M.job_id > 0 then
                vim.fn.jobstop(M.job_id)
            end
        end,
    })
end

--- A test call to plumber that echos the input
---@param word string The word to echo in the test call to plumber
function M.say(word)
    local url = construct_plumber_url("echo")
    async_curl(url, {
        headers = { ["Content-Type"] = "application/json" },
        body = { msg = word or "Hello, from plumber!" }
    })
end

M.kill_plumber = function()
    if M.job_id == nil then
        return "Plumber is not running"
    end
    vim.fn.jobstop(M.job_id)
    M.job_id = nil
end

--- Run testthat tests on a file
--- @param test_file string The complete path of the test file to run the tests on
--- @param source_dir string The directory of the source package (used for devtools
function M.run_testthat(test_file, source_dir)
    if not M.plumber_is_running() then
        return "Plumber is not running so cannot run testthat tests"
    end
    local curl = require "plenary.curl"
    local data_arg = vim.fn.json_encode({
        test_file = test_file,
        current_dir = source_dir,
    })
    local url = construct_plumber_url("test")
    local opts = {
        body = data_arg,
        headers = {
            content_type = "application/json",
        },
    }
    local curl_result = curl.post(url, opts)
    return decode_curl_result(curl_result)
end

local function update_counts(counts, failed)
    counts.pass = counts.pass - #failed
    for _, value in pairs(failed) do
        if value.severity == vim.diagnostic.severity.WARN then
            counts.warning = counts.warning + 1
        elseif value.severity == vim.diagnostic.severity.ERROR then
            counts.failure = counts.failure + 1
        else
            error("Unknown severity: " .. value.severity)
        end
    end
    return counts
end

local function add_timings(all_lines, timings, buf_nr, ns)
    local line_number = timings.nearest_line[1]
    local block_name = timings.block[1]
    -- will have type userdata when there is a syntax error in the test file
    if not line_number or not block_name or type(block_name) == "userdata" then
        return
    end
    -- Escape any special characters
    block_name = block_name:gsub("%W", "%%%0")
    local found
    repeat
        line_number = line_number - 1
        found = (all_lines[line_number]:match("^test_that") and
            all_lines[line_number]:match(block_name))
    until line_number == 1 or found
    if line_number == 1 then
        print("Couldnt find test_that line")
        return
    end
    local timing = timings.timing[3]
    local icon = M.options.outcome_icons.timing
    local virt_text = { { icon .. " " .. timing .. " " .. icon } }
    vim.api.nvim_buf_set_extmark(buf_nr, ns, line_number - 1, 0, {
        virt_text = virt_text,
    })
end

local outcome_severity = {
    expectation_warning = vim.diagnostic.severity.WARN,
    expectation_failure = vim.diagnostic.severity.ERROR,
    expectation_error = vim.diagnostic.severity.ERROR,
}

local function process_diagnostics_and_tag(block, buf_nr, ns, failed)
    local icon, diagnostic_severity, message
    for _, value in pairs(block) do
        local outcome = value.result
        local first_outcome = outcome[1]
        local line_number = value.location[1] - 1
        if not first_outcome:match("^expectation_") then
            error("unknown outcome" .. first_outcome)
        else
            icon = M.options.outcome_icons[first_outcome] or "❓ unexpected outcome ❓"
        end
        diagnostic_severity = outcome_severity[first_outcome]
        message = M.options.outcome_message[first_outcome]
        if diagnostic_severity then
            table.insert(failed, {
                bufnr = buf_nr,
                lnum = line_number,
                col = 0,
                severity = diagnostic_severity,
                source = "rautotest",
                message = message .. value.message[1]
            })
        end
        vim.api.nvim_buf_set_extmark(buf_nr, ns, line_number, 0, {
            virt_text = { { icon } },
        })
    end
    return failed
end

local function process_all_blocks(testthat_output, buf_nr, ns)
    local failed = {}
    local all_lines = vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false)
    local counts = {
        pass = 0,
        warning = 0,
        failure = 0,
    }
    for _, value in pairs(testthat_output) do
        if value.results then
            failed = process_diagnostics_and_tag(value.results, buf_nr, ns, failed)
            counts.pass = counts.pass + #value.results
        end
        if value.timings then
            add_timings(all_lines, value.timings, buf_nr, ns)
        end
    end
    if #failed > 0 then
        counts = update_counts(counts, failed)
    end
    local warn_string = counts.warning == 1 and " warning" or " warnings"
    local fail_string = counts.failures == 1 and " failure" or " failures"
    vim.api.nvim_buf_set_extmark(buf_nr, ns, 0, 0, {
        virt_text = {
            { " " .. counts.pass .. " passed",      "TestPassed" },
            { " " .. counts.warning .. warn_string, "TestWarning" },
            { " " .. counts.failure .. fail_string, "TestFailure" },
        },
        virt_text_pos = "eol",
        hl_mode = "combine",
    })
    return failed
end

M.run_plumber_testthat = function(file_to_test, buf_nr)
    if not M.plumber_is_running() then
        return "Plumber is not running, please run it before attempting to run tests"
    end
    if buf_nr == nil then
        buf_nr = vim.api.nvim_get_current_buf()
        file_to_test = vim.api.nvim_buf_get_name(buf_nr)
    end
    local current_working_directory = vim.loop.cwd()
    if current_working_directory == nil then return end
    local args = {
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = {
            test_file = file_to_test,
            current_dir = current_working_directory,
        },
        on_success = function(response, raw)
            if response ~= nil and response then
                local ns = M.namespace
                vim.api.nvim_buf_clear_namespace(buf_nr, ns, 0, -1)
                local failed = process_all_blocks(response, buf_nr, ns)
                local diagnostic_opts = { virtual_text = false, }
                vim.diagnostic.set(ns, buf_nr, failed, diagnostic_opts)
            else
                print("Plumber testthat did not respond as expected: " .. raw)
            end
        end,
        on_exit = function(code)
            if code ~= 0 then
                print("Plumber testthat command failed with exit code: " .. code)
            end
        end,
    }
    async_curl(construct_plumber_url("test"), args)
end

-- Clear diagnostics and extmarks for the current buffer
M.clear_diagnostics = function()
    local ns = M.namespace
    local buf_nr = vim.api.nvim_get_current_buf()
    vim.diagnostic.reset(ns, buf_nr)
    vim.api.nvim_buf_clear_namespace(buf_nr, ns, 0, -1)
end

return M
