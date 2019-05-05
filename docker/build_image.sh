#/usr/bin/env bash
cp ../run.sh ./run.sh
docker build . -t "openblas-npy-build"
