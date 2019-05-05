#/usr/bin/env bash

docker run -it openblas-npy-build 2>&1 | tee out1.tmp
cat out1.tmp | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" > run.log
rm out1.tmp

