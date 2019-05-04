#!/usr/bin/env bash

########################
####### helpers ########
########################

NTHREADS=`nproc --all`
NCORES=`grep -m 1 'cpu cores' /proc/cpuinfo | grep -io "[0-9]\+"` 

checkout_latest_release() {
    git fetch --tags
    latestTag=$(git describe --tags `git rev-list --tags --max-count=1`)
    git checkout $latestTag
}

########################
########################


# install Debian dependencies
sudo apt update
# use default g++/gcc versions -> configure to use
# specified ones using update-alternatives?
sudo apt install build-essential python3-dev python3-setuptools python3-pip make gcc g++ \
git gfortran

##################################
# more helpers with dependencies #
##################################

MARCH=`gcc -c -Q -march=native --help=target | grep march | grep -io  "\s[a-z]\+" | grep -io "[a-z]\+"`
echo 'projects will be compiled for "$MARCH" microarchitecuture'
echo 'please check if this is your suitable targer microarch!'

##################################
##################################


##################################
########### OpenBLAS #############
##################################


# clone latest OpenBLAS
git clone https://github.com/xianyi/OpenBLAS.git
cd OpenBLAS
checkout_latest_release

# enable huge pages - https://github.com/xianyi/OpenBLAS/blob/develop/GotoBLAS_05LargePage.txt
# number of cores or threads? 
# how to know which number of threads to use? -> NTHREADS is currently being used, use NCORES 
# you find it better suited
HPAGE=$((NTHREADS * 8))
sudo echo  0 > /proc/sys/vm/nr_hugepages		# need to be reset
sudo echo $HPAGE > /proc/sys/vm/nr_hugepages		# add 1 extra page
sudo echo 3355443200 > /proc/sys/kernel/shmmax   	# just large number
sudo echo 3355443200 > /proc/sys/kernel/shmall	

sudo echo "* hard memlock unlimited" >> /etc/security/limits.conf
sudo echo "* soft memlock unlimited" >> /etc/security/limits.conf

sudo service sshd restart

# check if I should compile with OpenMP as it's compromised
# https://github.com/xianyi/OpenBLAS/blob/develop/GotoBLAS_03FAQ.txt
# line 59.
# Will this be compiled for native march?
make BINARY=64 TARGET=$MARCH DYNAMIC_ARCH=0 USE_OPENMP=1 \
CC=gcc FC=gfortran USE_THREAD=1 NO_LAPACK=0 NO_LAPACKE=0 \
BUILD_LAPACK_DEPRECATED=1 NO_WARMUP=0 NO_AFFINITY=0 \
NO_AVX=0 NO_AVX2=0 NO_PARALLEL_MAKE=0 MAKE_NB_JOBS=$NTHREADS \
PREFIX=/opt/OpenBLAS

##################################
##################################



##################################
############## numpy #############
################################## 

##################################
##################################


# select version for which numba can be installed #
# this one will fetch latest release
# git clone https://github.com/numpy/numpy
# cd numpy
# checkout_latest_release
