local tmp_dir = "/tmp"

local repos = {
    plenary = { github = "nvim-lua/plenary.nvim", dir = "plenary.nvim" },
    telescope = { github = "nvim-lua/telescope.nvim", dir = "telescope.nvim" },
}

vim.opt.rtp:append(".")
for _, values in pairs(repos) do
    local repo_dir = tmp_dir .. "/" .. values.dir
    local is_not_a_directory = vim.fn.isdirectory(repo_dir) == 0
    if is_not_a_directory then
        vim.fn.system({"git", "clone", "https://github.com/" .. values.github, repo_dir})
    end
    vim.opt.rtp:append(repo_dir)
end

vim.cmd("runtime plugin/plenary.vim")
vim.cmd("runtime plugin/telescope.nvim")
vim.cmd("runtime plugin/rautotest")
require("plenary.busted")
require("telescope.actions")
require("rautotest")
