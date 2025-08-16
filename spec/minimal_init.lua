local tmp_dir = "/tmp"

require 'busted.runner'()

vim.cmd("runtime plugin/rautotest")
require("rautotest")
