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

## Running Internet tests

The Internet tests have been set up so that they should be able to run on
both Internet 5 and Internet 6 systems (as well as being based on the tests
run by Pyromaniac to exercise its stack).

The tests try to close sockets at the end of the run to ensure that they
are safe for runing on live systems, but expect to have to restart the
Internet module between runs (eg `rmreinit Internet` and
`ifconfig lo0 127.0.0.1`).

The replacement strings used within the tests should ensure that the
results of the tests are normalised so that socket numbers and other
differences are ignored.

Internet 5 test results are from running on RPCEmu with Select 4.
Internet 6 test results are from running on RISC OS Pyromaniac with its
native stack, at present.

Testing each of the stacks should be a matter of running:

    /!RunTests tests-internet-5/txt
    /!RunTests tests-internet-6/txt

But the Internet 6 results have not been verified - they will differ as
they have largely been copied from the Pyromaniac results where no IPv6
result was present.
