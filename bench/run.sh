#! /usr/bin/env bash

# Make a 1MiB test file.
if [ ! -f bench-test.txt ]; then
#    for ((i=1;i<=65536;i++))
    for ((i=1;i<=65536;i++))
    do
        echo "             foo" >> bench-test.txt
    done
fi

# gunzip --stdout /usr/share/man/man1/bash.1.gz > bash.1.man

cabal v2-build bench-string
cabal v2-build bench-text
cabal v2-build bench-bytestring

# diff <(sed 's/bash/fnord/g' < bash.1.man) <(cabal v2-run bench-string < bash.1.man)
# diff <(sed 's/bash/fnord/g' < bash.1.man) <(cabal v2-run bench-bytestring < bash.1.man)
# diff <(sed 's/foo/bar/g' < bench-test.txt) <(cabal v2-run bench-string < bench-test.txt)
# diff <(sed 's/foo/bar/g' < bench-test.txt) <(cabal v2-run bench-bytestring < bench-test.txt)

perf stat sed 's/foo/bar/g' < bench-test.txt 1> /dev/null
perf stat cabal v2-run bench-string < bench-test.txt 1> /dev/null
#perf stat cabal v2-run bench-text < bench-test.txt 1> /dev/null
perf stat cabal v2-run bench-bytestring < bench-test.txt 1> /dev/null

