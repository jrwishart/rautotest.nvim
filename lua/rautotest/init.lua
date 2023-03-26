local M = {}

M.settings = {
    source_dir = "/R",
    test_dir = "/tests/testthat",
    test_cmd = ": silent RTestPackage ",
    pkgname = "rautotest",
}

M.augroup = vim.api.nvim_create_augroup(M.settings.pkgname, { clear = true })

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
                print(entry)
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

M.init_pair = function(source_file, test_file)
    local test_filename = vim.fn["fnamemodify"](test_file, ":t:r")
    local pair = {
        source_filename_with_path = source_file,
        source_filename = vim.fn["fnamemodify"](source_file, ":t"),
        test_filename_with_path = test_file,
        test_filename = test_filename,
        test_pattern = test_filename:gsub("^test%-", ""),
    }
    local existing_autocmd = vim.api.nvim_get_autocmds({ group = M.settings.pkgname })
    -- Check pair isn't already in the list
    if #existing_autocmd > 0 then
        local pattern_matches
        local test_matches
        for _, autocmd in ipairs(existing_autocmd) do
            pattern_matches = autocmd.pattern == pair.source_filename
            test_matches = autocmd.command == M.settings.test_cmd .. pair.test_pattern
            if pattern_matches and test_matches then
                return
            end
        end
    end
    M.make_autocmd(pair)
end

M.make_autocmd = function(pair_table)
    local clean_test_filename = pair_table.test_filename:gsub("^test%-", "")
    vim.api.nvim_create_autocmd('BufWritePost', {
        group = M.settings.pkgname,
        pattern = pair_table.source_filename,
        command = M.settings.test_cmd .. clean_test_filename,
    })
end

M.find_files = function()
    local current_buffer = vim.api.nvim_get_current_buf()
    -- Check the buffer is a file
    if vim.api.nvim_buf_get_option(current_buffer, "buftype") ~= "" then
        print("Buffer is not a file")
        return
    end
    local current_filename_with_path = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
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
                M.init_pair(current_filename_with_path, test_filename)
            end)
            return true
        end,
    }
    require'telescope.builtin'.find_files(opts)
end

M.remove_tests = function()
    local autocmds = vim.api.nvim_get_autocmds({ group = M.settings.pkgname })
    if #autocmds == 0 then
        print("No tests to remove")
        return
    end
    if #autocmds == 1 then
        vim.api.nvim_del_autocmd(autocmds[1].id)
        return
    end
    local entries = {}
    for _, value in ipairs(autocmds) do
        local source_file = value.pattern
        local test_file = value.command:gsub("^: silent RTestPackage ", "")
        local id = value.id
        local pair_name = source_file .. " <--> " .. test_file
        table.insert(entries, { pair_name, id })
    end
    M.autocmd_picker(entries)
end

return M
