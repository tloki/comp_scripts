#/usr/bin/env bash

docker run -it openblas-npy-build 2>&1 | tee out.log
