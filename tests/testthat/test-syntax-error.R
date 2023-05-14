context("Test file has syntax error")

1 + "1"

test_that("Can get bar", {
    expect_equal(foo(), "bar")
    expect_equal(foo("baz"), "bar")
})

test_that("Can add numbers", {
    expect_equal(bar(1), 2)
    expect_equal(bar(7), 8)
    expect_equal(bar(100L), 101)
})
