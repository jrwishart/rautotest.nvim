# rautotest.nvim

An nvim plugin for R development that runs and decorates individual [testthat](https://testthat.r-lib.org/) files in a buffer with test results. It does this by running an external R process via the [plumber](www.rplumber.io/) package, which allows you to run R code as a web service. The plumber process is then used to call [devtools](https://cran.r-project.org/web/packages/devtools/index.html) to load the R package and [testthat](https://testthat.r-lib.org/) to run the tests.

## 📦 Installation

Use your favorite plugin manager to install rautotest.nvim and its dependencies (currently depends on R with plumber, testthat and devtools libraries installed). For example,

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

