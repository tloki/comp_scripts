#/usr/bin/env bash
cp ../run.sh ./run.sh
docker build . -t "openblas-npy-build" 2>&1 | tee out2.tmp
cat out2.tmp | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" > build.log
rm out2.tmp
