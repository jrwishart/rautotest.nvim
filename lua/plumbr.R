#* Echo back the input
#* @param msg The message to echo, used for testing
#* @post /echo
function(msg = "") {
    list(
        msg = paste0("The message is: '", msg, "'"),
        devtools = requireNamespace("devtools", quietly = TRUE),
        testthat = requireNamespace("testthat", quietly = TRUE)
    )
}

#* Add two numbers
#* @param x The first number
#* @param y The second number
#* @post /add
function(x, y) {
    as.numeric(x) + as.numeric(y)
}

processResults <- function(results) {
    outcome <- attr(results, "class")
    if (FALSE && startsWith(outcome[1], "expectation"))
        outcome <- outcome[1]
    location <- results[["srcref"]] |> unclass()
    message <- results[["message"]]
    list(result = outcome, location = location, message = message)
}

processTestBlock <- function(block) {
    test <- block[["test"]]
    timing <- block[c("user", "system", "real")] |> unlist()
    results <- lapply(block[["results"]], processResults)
    nearest.line <- results[[1]][["location"]][1L]
    timings <- list(block = test, timing = timing, nearest_line = nearest.line)
    list(results = results, timings = timings)
}

#* Run testthat on test files
#* @param test_file The complete file path of the test file to run
#* @param current_dir The path to the package base directory
#* @serializer json list(force = TRUE)
#* @post /test
function(test_file, current_dir) {
    if (missing(test_file))
        stop("test_file is missing and needs to be specified")
    if (missing(current_dir))
        stop("current.dir is missing and needs to be specified")
    if (!requireNamespace("devtools", quietly = TRUE))
        stop("devtools package is not installed and needed to load package")
    if (!dir.exists(current_dir))
        stop("current_dir :", current_dir, " does not exist")
    devtools::load_all(current_dir)
    if (!requireNamespace("testthat", quietly = TRUE))
        stop("testthat package is not installed and required to run tests")

    if (!file.exists(test_file))
        stop("test file not found: ", test_file)
    testthat::test_file(test_file, reporter = testthat::ListReporter) |>
        lapply(processTestBlock)
}
