-- make sure this file is loaded only once
if vim.g.rautotest == 1 then
    return
end
vim.g.rautotest = 1

local rautotest = require("rautotest")

vim.api.nvim_create_user_command(
    "RAutotestAddTestLinks",
    rautotest.add_test_links,
{})

vim.api.nvim_create_user_command(
    "RAutotestRemoveTestLinks",
    rautotest.remove_test_links,
{})
