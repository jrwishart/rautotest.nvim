# rautotest.nvim

An nvim plugin for automating test files in an R package when an R source file buffer is saved/written.

## 📦 Installation

Use your favorite plugin manager to install rautotest.nvim and its dependencies (currently depends on R with plumber and devtools libraries installed). For example,

### [packer](https://github.com/wbthomason/packer.nvim)

```lua
use {
    "jrwishart/rautotest.nvim",
    ft = {'r'}, -- optional, only load plugin for r files
}
```

### [lazy](https://github.com/folke/lazy.nvim)

```lua
{
    jrwishart/rautotest.nvim,
    ft = {'r'} -- optional, only load plugin for r files
}
```

## ✨ Usage

Load to a testthat file from your R package into a buffer, and run the command

```
:RAutotestTestFile
```

![rautotest.nvim demo](https://raw.githubusercontent.com/jrwishart/rautotest.nvim/master/demo.gif)

Doing so will run an external R process via `plumber` to run the tests in then file and then decorate the buffer with the results of the tests.

If you wish to remove the decorations from the buffer, you can run the command

```
:RAutotestClearMarks
```

