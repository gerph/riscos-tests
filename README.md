# Tests for RISC OS

This repository contains tests for RISC OS interfaces. It is intended to
provide regression tests to check that the interfaces are unchanged, or
that if they change they will do so in a structured manner.

Only some of the tests are present in this repository.


# Building

The makefile will build all the source files.
For ease, the binaries are checked in, as this allows testing without the
build tools being available.


# Running tests

There is a perl script, test.pl which is intended for running the test
files.

The test descriptions are present for a few of the tests:

* `tests-core.txt`
* `tests-vdu.txt`
* `tests-readargs.txt`

To run the scripts, use the !RunTests script, thus:

    /!RunTests tests-core/txt

