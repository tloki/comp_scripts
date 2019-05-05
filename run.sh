#!/usr/bin/env bash

########################
####### helpers ########
########################

# set some variables to be used later in the process

NTHREADS=`nproc --all`	# get number of cpu threads
NCORES=`grep -m 1 'cpu cores' /proc/cpuinfo | grep -io "[0-9]\+"`  # get number of cpu cores

checkout_latest_release() {
    git fetch --tags
    latestTag=$(git describe --tags `git rev-list --tags --max-count=1`)
    git checkout $latestTag
}

echo "detected $NCORES CPU cores"
echo "detected $NTHREADS CPU threads"

########################
########################


########################
# Debian deps install ##
########################

# install Debian dependencies
sudo apt update
# use default g++/gcc versions -> use update-alternatives if you want another gcc/g++ version
sudo apt install build-essential python3-dev python3-setuptools python3-pip make gcc g++ \
git gfortran -y

########################
########################


##################################
# more helpers with dependencies #
##################################

# get microarchitecture codename and store it in variable
MARCH=`gcc -c -Q -march=native --help=target | grep march | grep -io  "\s[a-z]\+" | grep -io "[a-z]\+"`

# override MARCH if you'd like it to be compiled for another microarch
MARCH=skylake # 'skylake' is also suitable for kabylake

# gcc and gfortran versions (I think they need to be matched)
# - change values to ones suitable (probably best to use gcc/g++)
GCCV=gcc-8
GXXV=g++-8
GFORTV=gfortran-8

# OpenBLAS target,
# find available ones here https://github.com/xianyi/OpenBLAS/blob/develop/TargetList.txt
OBTARGET=HASWELL

echo ""
echo "projects will be compiled using \"$GCCV\" for \"$MARCH\" microarchitecuture"
echo "please check if this is your suitable target microarch!"
echo "OpenBLAS will be compiled for \"$OBTARGET\""
echo ""
sleep 5

sudo apt install $GCCV $GXXV $GFORTV -y

##################################
##################################


##################################
########### OpenBLAS #############
##################################

# clone latest release (tag) of OpenBLAS
rm -rf OpenBLAS
git clone https://github.com/xianyi/OpenBLAS.git
cd OpenBLAS
checkout_latest_release

# enable huge pages - https://github.com/xianyi/OpenBLAS/blob/develop/GotoBLAS_05LargePage.txt
# TODO: should I use number of cores or threads for pages size setup?
HPAGE=$((NTHREADS * 8))
sudo echo  0 > /proc/sys/vm/nr_hugepages		# need to be reset
sudo echo $HPAGE > /proc/sys/vm/nr_hugepages		# add 1 extra page
sudo echo 3355443200 > /proc/sys/kernel/shmmax   	# just large number
sudo echo 3355443200 > /proc/sys/kernel/shmal

sudo echo "* hard memlock unlimited" >> /etc/security/limits.conf
sudo echo "* soft memlock unlimited" >> /etc/security/limits.conf

sudo service sshd restart
echo ""

# TODO: check if I should compile with OpenMP as it's compromised
# https://github.com/xianyi/OpenBLAS/blob/develop/GotoBLAS_03FAQ.txt
# line 59.
# Will this be compiled for native march? (no "TARGET" flag specified, but according to
# https://github.com/xianyi/OpenBLAS/blob/develop/GotoBLAS_02QuickInstall.txt line 23 - it will be chosen automagicaly 
make clean
make BINARY=64 DYNAMIC_ARCH=0 USE_OPENMP=1 \
CC=$GCCV FC=$GFORTV USE_THREAD=1 \
NO_WARMUP=0 TARGET=$OBTARGET \
NO_PARALLEL_MAKE=0 MAKE_NB_JOBS=$NTHREADS \
PREFIX=/opt/OpenBLAS


#NO_LAPACKE=0 -> see below
#NO_LAPACK=0 - is this a bug? If I set this to be equal to 0, I have this problem https://github.com/xianyi/OpenBLAS/issues/250
# which seems closed but it does affect me (although it's not exactly the same setup)
# BUILD_LAPACK_DEPRECATED=1 \ not sure if I need this...

# according to https://github.com/xianyi/OpenBLAS/blob/develop/Makefile.rule
# Note: enabling affinity has been known to cause problems with NumPy and R
# NO_AFFINITY = 0 -> leaving default 1 for now because of problems above
# NO_AVX=0 NO_AVX2=0 - did not bother to set as I was afraid if it will be logically inverted (i.e. if I really set them to 0, avx/2 won't be enabled)

sudo make PREFIX=/opt/OpenBLAS install

cd ..

##################################
##################################


##################################
############## numpy #############
################################## 

sudo -H pip3 install cython

sudo rm -rf numpy
git clone https://github.com/numpy/numpy.git
cd numpy
checkout_latest_release
touch site.cfg

echo "[ALL]"							>> site.cfg
echo "library_dirs = /usr/local/lib:/opt/OpenBLAS/lib"		>> site.cfg
echo "include_dirs = /usr/local/include:/opt/OpenBLAS/include"	>> site.cfg
echo "[atlas]"							>> site.cfg
echo "atlas_libs = openblas"					>> site.cfg
echo "include_dirs = /opt/OpenBLAS/include"			>> site.cfg
echo "library_dirs = /opt/OpenBLAS/lib"				>> site.cfg
echo "[lapack]"							>> site.cfg
echo "lapack_libs = openblas"					>> site.cfg
echo "library_dirs = /usr/local/lib"				>> site.cfg
echo "include_dirs = /opt/OpenBLAS/include"			>> site.cfg
echo "[openblas]"						>> site.cfg
echo "libraries = openblas"					>> site.cfg
echo "library_dirs = /opt/OpenBLAS/lib"				>> site.cfg
echo "include_dirs = /opt/OpenBLAS/include"			>> site.cfg
echo "runtime_library_dirs = /opt/OpenBLAS/lib"			>> site.cfg


echo "building numpy ($MARCH)"
echo ""

# one may also disable debugging (not just here but for openblas also?)
# -DNDEBUG (but how to use it? - after -j ? https://www.numpy.org/devdocs/user/building.html)
# seems like it's enabled by default!
CFLAGS="-O2 -march=$MARCH -m64" \
CXXFLAGS="-O2 -march=$MARCH -m64" \
FFLAGS="-O2 -march=$MARCH -m64" \
CC=$GCCV \
CXX=$GCCV \
FC=$GFORTV \
BLAS=/opt/OpenBLAS/lib/libopenblas.a \
LAPACK=/opt/OpenBLAS/lib/libopenblas.a \
LD_LIBRARY_PATH=/opt/OpenBLAS/lib/${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} \
NPY_BLAS_ORDER=openblas,blis \
BLAS=openblas LAPACK=openblas \
LAPACK=openblas \
ATLAS=openblas \
python3 setup.py build -j $NTHREADS --fcompiler=gfortran

echo "installing numpy"
echo ""

# will be installed in /usr/local/lib/python3.6/dist-packages/
sudo python3 setup.py install

cd ..
# test config:

python3 -c "import numpy as np; np.__config__.show()"

# run tests:
sudo -H pip3 install pytest nose pytz
#python3 -c 'import numpy; numpy.test("full");'
python3 numpy/runtests.py -m full -- -ras

# 6 tests failing for now:

# TestCholesky.test_basic_property
# E       numpy.linalg.LinAlgError: Matrix is not positive definite;
# err        = 'invalid value'
# flag       = 8

# and 5 of those:
# TestGauss.test_100
# E       AssertionError: (something)

# test yourself if every core on your system is active

echo "matmul test took:"
python3 -c "import timeit; print(timeit.Timer(\"import numpy as np;size = 10000;a = np.random.random_sample((size, size));b = np.random.random_sample((size, size));n = np.dot(a,b)\").timeit(number=2))"
echo "seconds"
echo "sleep 5"

# for i7 8650U on Ubuntu 18.04, all threads used, it takes 41 seconds

##################################
##################################
