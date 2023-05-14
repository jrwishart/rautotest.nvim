# rautotest.nvim

An nvim plugin for automating test files in an R package when an R source file buffer is saved/written.

## 📦 Installation

Use your favorite plugin manager to install rautotest.nvim and its dependencies (currently depends on [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) and [mllg/vim-devtools-plugin](https://github.com/mllg/vim-devtools-plugin)). For example,

### [packer](https://github.com/wbthomason/packer.nvim)

```lua
use {
    "jrwishart/rautotest.nvim",
    ft = {'r'}, -- optional, only load plugin for r files
    requires = {
        "nvim-telescope/telescope.nvim",
        "mllg/vim-devtools-plugin"
    }
}
```

### [lazy](https://github.com/folke/lazy.nvim)

```lua
{
    jrwishart/rautotest.nvim,
    dependencies = { 'telescope.nvim', 'mllg/vim-devtools-plugin' },
    ft = {'r'} -- optional, only load plugin for r files
}
```

## ✨ Usage

When you save a file, `rautotest.nvim` will run the test file associated with the source file using the `:RTestPackage` command is invoked with the test file that is linked. The test files that are linked need to be specified by the user. The workflow is as follows:

1. Lnk the files: open the desired R source file in a buffer and then run the command

```
:RAutotestAddTestLinks
```

Doing so will open a telescope prompt of all the identified files in the test directory. Select the test file that corresponds to the source file you are currently editing.

2. Save the source file in the buffer. This will run the test file that is linked to the source file.


To remove the link to prevent the tests running when the buffer is saved/written, run the command

```
:RAutotestRemoveTestLinks
```

If there is only one file linked it will be removed. If there are multiple files linked, then another telescope prompt will open to select the file to remove.
