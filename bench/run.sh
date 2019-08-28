
gunzip --stdout /usr/share/man/man1/bash.1.gz > bash.1.man

cabal v2-build bench-bash




diff <(sed 's/bash/fnord/g' < bash.1.man) <(cabal v2-run bench-bash < bash.1.man)

perf stat sed 's/bash/fnord/g' < bash.1.man 1> /dev/null

perf stat cabal v2-run bench-bash < bash.1.man 1> /dev/null
