local M = {}

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
        vim.api.nvim_create_augroup(M.options.namespace, { clear = true })
    end
    M.run_plumber()
    return M
end

local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local pickers = require "telescope.pickers"
local conf = require("telescope.config").values
local finders = require "telescope.finders"

M.autocmd_picker = function(entries, opts)
    opts = opts or {}
    pickers.new(opts, {
        prompt_title = "Select the source <---> test pair to remove",
        finder = finders.new_table {
            results = entries,
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry[1],
                    ordinal = entry[1],
                }
            end
        },
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, _)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selected_entry = action_state.get_selected_entry()
                local id_to_remove = selected_entry.value[2]
                vim.api.nvim_del_autocmd(id_to_remove)
            end)
            return true
        end,
    }):find()
end

M.check_autocmd_exists = function(source_buffer, source_name, test_name)
    local existing_autocmd = vim.api.nvim_get_autocmds({ group = M.options.namespace })
    -- Check pair isn't already in the list
    if #existing_autocmd > 0 then
        local source_matches, desc_matches
        for _, autocmd in ipairs(existing_autocmd) do
            source_matches = autocmd.buffer == source_buffer
            desc_matches = autocmd.desc == source_name .. " --> " .. test_name
            if source_matches and desc_matches then
                return true
            end
        end
    end
    return false
end

M.make_autocmd = function(source_buffer, test_filename)
    local source_name = vim.api.nvim_buf_get_name(source_buffer)
    local autocmd_exists = M.check_autocmd_exists(source_buffer, source_name, test_filename)
    if autocmd_exists then
        print("Pair already exists")
        return
    end
    local test_buf_exists = vim.fn.bufexists(test_filename)
    if test_buf_exists == 0 then -- open new buffer
        local current_buf_nr = vim.api.nvim_get_current_buf()
        vim.api.nvim_command("silent e " .. test_filename)
        vim.api.nvim_set_current_buf(current_buf_nr)
    end
    local test_buffer = vim.fn.bufnr(test_filename)
    local test_name = vim.api.nvim_buf_get_name(test_buffer)
    vim.api.nvim_create_autocmd('BufWritePost', {
        group = M.namespace,
        buffer = source_buffer,
        desc = source_name .. " --> " .. test_name,
        callback = function()
            M.run_plumber_testthat(test_name, test_buffer)
        end,
    })
end

M.add_test_links = function()
    if not M.plumber_is_running() then
        print("Run plumber first")
        return
    end
    local current_buffer = vim.api.nvim_get_current_buf()
    -- Check the buffer is a file
    if vim.api.nvim_buf_get_option(current_buffer, "buftype") ~= "" then
        print("Buffer is not a file")
        return
    end
    local source_buffer = vim.api.nvim_get_current_buf()
    local current_filename_with_path = vim.api.nvim_buf_get_name(source_buffer)
    -- Remove the full path and only show the filename
    local current_filename = vim.fn["fnamemodify"](current_filename_with_path, ":t")
    local cwd = vim.fn.getcwd()
    local opts = {
        prompt_title = "Select test file to run when " .. current_filename .. " is saved",
        follow = 'true',
        layout_strategy = "horizontal",
        layout_config = {
            width = 0.95,
        },
        cwd = cwd .. "/tests/testthat",
        attach_mappings = function(prompt_bufnr, _)
            actions.select_default:replace(function()
                local test_filename = action_state.get_selected_entry()[1]
                actions.close(prompt_bufnr)
                local full_test_filename = cwd .. "/tests/testthat/" .. test_filename
                M.make_autocmd(current_buffer, full_test_filename)
            end)
            return true
        end,
    }
    require'telescope.builtin'.find_files(opts)
end

M.remove_test_links = function()
    local autocmds = vim.api.nvim_get_autocmds({ group = M.options.namespace })
    if #autocmds == 0 then
        return
    end
    if #autocmds == 1 then
        vim.api.nvim_del_autocmd(autocmds[1].id)
        return
    end
    local entries = {}
    for _, value in ipairs(autocmds) do
        local id = value.id
        local pair_name = value.desc
        table.insert(entries, { pair_name, id })
    end
    M.autocmd_picker(entries)
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

--- Function to decode the json result and throw an error if the curl call failed
--- @param curl_result table The result of the curl call
local decode_curl_result = function(curl_result)
    if curl_result == nil or curl_result.status ~= 200 or curl_result.body == nil then
        error("curl failed: " .. vim.inspect(curl_result))
    end
    return vim.fn.json_decode(curl_result.body);
end

local port_check_fun_string = function()
    if vim.fn.has("macunix") == 1 then
        return "lsof -i -P"
    end
    error("Only macunix is supported at the moment")
end

--- Takes a path and constructs a plumber url based off the plumber port
--- @param path string The path to append to the url
local construct_plumber_url = function(path)
    return "http://localhost:" .. M.options.plumber_port .. "/" .. path
end

M.plumber_is_running = function()
    if M.options.plumber_port == nil then
        return false
    end
    local port_check_string = port_check_fun_string()
    local check_port = vim.fn.system(port_check_string .. " | grep LISTEN | grep " .. M.options.plumber_port)
    return string.sub(check_port, 1, 2) == "R "
end

M.run_plumber = function()
    if M.plumber_is_running() then
        print("Plumber is already running")
        return
    end
    local current_path = resolve_path()
    local src_file = vim.fn.fnamemodify(current_path, ":p:h") .. get_path_separator() .. "plumbr.R"
    local r_source = "'plumber::pr(\"" .. src_file .. "\") |> plumber::pr_run(port = " .. M.options.plumber_port ..")'"
    local chan_id = vim.fn.jobstart("R -q -e " .. r_source, {
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
        detach = true,
    })
    local pid = vim.fn.jobpid(chan_id)
    M.plumber_running = pid > 0
    M.plumber_pid = pid
    return pid
end

--- A test call to plumber that echos the input
---@param word string The word to echo in the test call to plumber
function M.say(word)
    local curl = require "plenary.curl"
    local opts = nil
    if word ~= nil then
        local json_word = vim.fn.json_encode({ msg = word })
        opts = {
            body = json_word,
            headers = { content_type = "application/json" },
        }
    end
    local url = construct_plumber_url("echo")
    local curl_result = curl.get(url, opts)
    return decode_curl_result(curl_result)
end

M.kill_plumber = function()
    if M.plumber_pid == nil or not M.plumber_pid then
        return "Plumber is not running"
    end
    local pid = M.plumber_pid
    local result = vim.loop.kill(pid, 2) -- 2 is SIGINT
    if result == 0 then
        M.plumber_pid = nil
    end
    return result
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
    local testthat_output = M.run_testthat(file_to_test, current_working_directory)
    if testthat_output == nil then
        return
    end
    local ns = M.namespace
    vim.api.nvim_buf_clear_namespace(buf_nr, ns, 0, -1)
    local failed = M.process_all_blocks(testthat_output, buf_nr, ns)
    local diagnostic_opts = { virtual_text = false, }
    vim.diagnostic.set(ns, buf_nr, failed, diagnostic_opts)
end

function M.process_all_blocks(testthat_output, buf_nr, ns)
    local failed = {}
    local all_lines = vim.api.nvim_buf_get_lines(buf_nr, 0, -1, false)
    local counts = {
        pass = 0,
        warning = 0,
        failure = 0,
    }
    for _, value in pairs(testthat_output) do
        if value.results then
            failed = M.process_diagnostics_and_tag(value.results, buf_nr, ns, failed)
            counts.pass = counts.pass + #value.results
        end
        if value.timings then
            M.add_timings(all_lines, value.timings, buf_nr, ns)
        end
    end
    if #failed > 0 then
        counts = M.update_counts(counts, failed)
    end
    local warn_string = counts.warning == 1 and " warning" or " warnings"
    local fail_string = counts.failures == 1 and " failure" or " failures"
    vim.api.nvim_buf_set_extmark(buf_nr, ns, 0, 0, {
        virt_text = {
            { " " .. counts.pass .. " passed", "TestPassed" },
            { " " .. counts.warning .. warn_string, "TestWarning" },
            { " " .. counts.failure .. fail_string, "TestFailure" },
        },
        virt_text_pos = "eol",
        hl_mode = "combine",
    })
    return failed
end

function M.update_counts(counts, failed)
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

local outcome_severity = {
    expectation_warning = vim.diagnostic.severity.WARN,
    expectation_failure = vim.diagnostic.severity.ERROR,
    expectation_error = vim.diagnostic.severity.ERROR,
}

function M.process_diagnostics_and_tag(block, buf_nr, ns, failed)
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
            virt_text = { {icon} },
        })
    end
    return failed
end

function M.add_timings(all_lines, timings, buf_nr, ns)
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
    local virt_text = { {icon .. " " .. timing .. " " .. icon} }
    vim.api.nvim_buf_set_extmark(buf_nr, ns, line_number - 1, 0, {
        virt_text = virt_text,
    })
end

M.clear_diagnostics = function()
    local ns = M.namespace
    local buf_nr = vim.api.nvim_get_current_buf()
    vim.diagnostic.reset(ns, buf_nr)
    vim.api.nvim_buf_clear_namespace(buf_nr, ns, 0, -1)
end

return M
