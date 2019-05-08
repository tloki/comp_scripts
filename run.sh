#!/usr/bin/env bash

#######################
####### config ########
#######################

# TODO: add all user config here -

# MARCH + auto
# TARGET

# custom release versions
# if not specified - latest release may will be selected
# warning - autorelease may select unstable or rc releases also!

# OpenBLAS version, https://github.com/xianyi/OpenBLAS/releases
OPBLS_BRANCH=
# numpy version, https://github.com/numpy/numpy/releases
NUMPY_BRANCH=
# scipy version, https://github.com/scipy/scipy/releases
SCIPY_BRANCH=
# opencv version, https://github.com/opencv/opencv/releases
OPNCV_BRANCH=

# gnu compilers version, 8 or 9 is encouraged as of May 2019.
GV=8

# numba compiler will be downloaded using pip (not building - not needed)
# there is a possibility that it's incompatible with latest numpy

# TODO:
# cufigurable script versions:
# Optimus Tensorflow + numba + opencv
# ROCm Tensorflow + numba + opencv
# nvidia TF + numba + opencv
# SkylakeX (does it need something other than TARGET and opencv skylake directive?) 
# tensorflow CPU?

########################
####### helpers ########
########################

# set some variables to be used later in the process

NTHREADS=`nproc --all`	# get number of cpu threads
NCORES=`grep -m 1 'cpu cores' /proc/cpuinfo | grep -io "[0-9]\+"`  # get number of cpu cores

checkout_latest_release2() {
    git fetch --tags
    latestTag=$(git describe --tags `git rev-list --tags --max-count=1`)
    git checkout $latestTag
}

checkout_latest_release() {
    URL=`git remote get-url origin`
    RLS_URL=$URL/releases/latest
    REDIR_URL=`curl -Ls -o /dev/null -w %{url_effective} $RLS_URL`
    RLS_VER=${REDIR_URL##*/}
    # echo $RLS_VER
    git checkout $RLS_VER
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
sudo apt install build-essential python3-dev python3-setuptools python3-pip make \
git -y

########################
########################


##################################
# more helpers with dependencies #
##################################

# get microarchitecture codename and store it in variable
MARCH=`gcc -c -Q -march=native --help=target | grep march | grep -io  "\s[a-z]\+" | grep -io "[a-z]\+"`

# override MARCH if you'd like it to be compiled for another microarch
MARCH=skylake # 'skylake' is also suitable for kabylake/R

# gcc and gfortran versions (I think they need to be matched)
# - change values to ones suitable (probably best to use gcc/g++)
VER=GV
GCCV=gcc-$VER
GXXV=g++-$VER
GFORTV=gfortran-$VER
CXXV=c++-$VER
CCV=cc-$VER

# OpenBLAS target,
# find available ones here https://github.com/xianyi/OpenBLAS/blob/develop/TargetList.txt
OBTARGET=HASWELL

echo ""
echo "projects will be compiled using \"$GCCV\" for \"$MARCH\" microarchitecuture"
echo "please check if this is your suitable target microarch!"
echo "OpenBLAS will be compiled for \"$OBTARGET\""
echo ""
#sleep 5

# update alternatives
# TODO: revert alternatives after compilation!
sudo apt install $GCCV $GXXV $GFORTV -y
sudo update-alternatives --install /usr/bin/gcc                      gcc                     /usr/bin/$GCCV                        50
sudo update-alternatives --install /usr/bin/gfortran                 gfortran                /usr/bin/$GFORTV                      50
sudo update-alternatives --install /usr/bin/g++                      g++                     /usr/bin/$GXXV                        50
sudo update-alternatives --install /usr/bin/x86_64-linux-gnu-gcc-ar  x86_64-linux-gnu-gcc-ar /usr/bin/x86_64-linux-gnu-gcc-ar-$VER 50
sudo update-alternatives --install /usr/bin/x86_64-linux-gnu-gcc     x86_64-linux-gnu-gcc    /usr/bin/x86_64-linux-gnu-gcc-$VER    50
# TODO: fix?
#sudo update-alternatives --install /usr/bin/c++                      c++                     /usr/bin/$CXXV                        50 

mkdir builds_comp_scripts
cd builds_comp_scripts
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

cd builds_comp_scripts
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
CXX=$GXXV \
FC=$GFORTV \
BLAS=/opt/OpenBLAS/lib/libopenblas.a \
LAPACK=/opt/OpenBLAS/lib/libopenblas.a \
LD_LIBRARY_PATH=/opt/OpenBLAS/lib/${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} \
NPY_BLAS_ORDER=openblas,blis \
BLAS=openblas LAPACK=openblas \
LAPACK=openblas \
ATLAS=openblas \
python3 setup.py build -j $NTHREADS --fcompiler=$GFORTV --compiler=$GCCV

echo "installing numpy"
echo ""

# will be installed in /usr/local/lib/python3.6/dist-packages/
sudo python3 setup.py install

cd ../..
# test config:

python3 -c "import numpy as np; np.__config__.show()"

# run tests:
sudo -H pip3 install pytest nose pytz
#python3 -c 'import numpy; numpy.test("full");'
python3 builds_comp_scripts/numpy/runtests.py -m full -- -ras

#echo "matmul test took:"
#python3 -c "import timeit; print(timeit.Timer(\"import numpy as np;size = 10000;a = np.random.random_sample((size, size));b = np.random.random_sample((size, size));n = np.dot(a,b)\").timeit(number=2))"
#echo "seconds"
#echo "sleep 5"
# for i7 8650U on Ubuntu 18.04, all threads used, it takes 41 seconds

##################################
##################################


##################################
############## scipy #############
##################################

cd builds_comp_scripts

sudo rm -rf scipy
git clone https://github.com/scipy/scipy.git
cd scipy
#checkout_latest_release
# TODO: un-hardcode this!
git checkout v1.2.1

cp ../numpy/site.cfg site.cfg


echo "building scipy ($MARCH)"
echo ""



#CFLAGS="-march=$MARCH -m64" \
#CXXFLAGS="-march=$MARCH -m64" \
#FFLAGS="-march=$MARCH -m64" \
CC=$GCCV \
CXX=$GXXV \
FC=$GFORTV \
BLAS=/opt/OpenBLAS/lib/libopenblas.a \
LAPACK=/opt/OpenBLAS/lib/libopenblas.a \
LD_LIBRARY_PATH=/opt/OpenBLAS/lib/${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} \
NPY_BLAS_ORDER=openblas,blis \
BLAS=openblas  \
LAPACK=openblas \
ATLAS=openblas \
python3 setup.py build -j $NTHREADS
#config       \
#build # \
#build_clib   \
#build_ext    \
echo "installing scipy"
sudo python3 setup.py install

cd ../..

# test config:
# python3 -c "import scipy as sp; sp.__config__.show()"

# run tests:
python3 builds_comp_scripts/scipy/runtests.py -m full -- -ras

##################################
##################################


###########################################
# coffe ###################################
###########################################


###########################################
############## opencv nonCuda #############
###########################################
exit 0

cd builds_comp_scripts

sudo rm -rf opencv
git clone https://github.com/opencv/opencv.git
git clone https://github.com/opencv/opencv_contrib.git
cd scipy
checkout_latest_release
cd ..
cd opencv_contrib
checkout_latest_release
cd ..

# deps
sudo apt-get purge x264 libx264-dev -y

sudo apt-get install build-essential cmake unzip pkg-config -y
sudo apt-get install libjpeg-dev libpng-dev libtiff-dev -y
sudo apt-get install libavcodec-dev libavformat-dev libswscale-dev libv4l-dev -y
sudo apt-get install libxvidcore-dev libx264-dev -y

# If you are using Ubuntu 18.04
sudo apt-get install libtiff-dev -y
sudo apt-get install libavcodec-dev libavformat-dev libswscale-dev  -y
sudo apt-get install libxine2-dev libv4l-dev -y
sudo apt-get install libtbb-dev -y
sudo apt-get install libfaac-dev libmp3lame-dev libtheora-dev -y
sudo apt-get install libvorbis-dev libxvidcore-dev -y
sudo apt-get install libopencore-amrnb-dev libopencore-amrwb-dev -y
sudo apt-get install x264 v4l-utils -y

# Optional dependencies
sudo apt-get install libprotobuf-dev protobuf-compiler -y
sudo apt-get install libgoogle-glog-dev libgflags-dev -y
sudo apt-get install doxygen -y

# packages you might find outdated, need newer version postfix or so
# packages above might need it too 
sudo apt install libgstreamer1.0-dev libgtk-3-dev libdc1394-22-dev \
qt5-default libgtk2.0-dev libgstreamer-plugins-base1.0-dev \
libgphoto2-dev libeigen3-dev libhdf5-dev -y

sudo apt install ccache libva-dev libavresample-dev libleptonica-dev  tesseract-ocr -y
sudo apt-get install libtesseract-dev -y

cd opencv
mkdir build
cd build

sudo -H pip3 install bs4 pylint tesserocr

CC=$CCV \
CXX=$CXXV \
FC=$GFORTV \
cmake \
    -D CMAKE_BUILD_TYPE=RELEASE \
    -D CMAKE_INSTALL_PREFIX=/usr/local \
    -D INSTALL_PYTHON_EXAMPLES=ON \
    -D INSTALL_C_EXAMPLES=ON \
    -D OPENCV_ENABLE_NONFREE=ON \
    -D OPENCV_EXTRA_MODULES_PATH=../../opencv_contrib/modules \
    -D PYTHON_EXECUTABLE=~/usr/bin/python3 \
    -D BUILD_EXAMPLES=ON \
    -D BUILD_DOCS=ON \
    -D BUILD_PERF_TESTS=ON \
    -D BUILD_TESTS=ON \
    -D INSTALL_TESTS=ON \
    -D WITH_EIGEN=ON \
    -D WITH_OPENMP=ON \
    -D WITH_CCACHE=ON \
    -D INSTALL_TESTS=ON \
    -D CPU_DISPATCH=DETECT \
    -D WITH_PTHREADS_PF=ON \
    -D WITH_V4L=ON \
    -D WITH_VA=ON \
    -D WITH_LAPACK=ON \
    -D WITH_IMGCODEC_PXM=ON \
    -D WITH_IMGCODEC_PFM=ON \
    -D WITH_QUIRC=ON \
    -D ENABLE_PRECOMPILED_HEADERS=ON \
    -D ENABLE_PYLINT=ON \
    -D CPU_BASELINE=AVX2 \
    ..

make -j $NTHREADS

sudo make install
sudo ldconfig

cd ../../..
pwd


#########################
###### other ############
#########################

sudo -H pip3 install nltk scikit-learn numba

##########################
###### tensorflow ########
##########################

# tutorial:
# https://www.pyimagesearch.com/2018/08/15/how-to-install-opencv-4-on-ubuntu/

# skylakeX
# CPU_DISPATCH=SKYLAKEX

# cuda:
# WITH_CUDA
# WITH_CUFFT
# WITH_CUBLAS
# WITH_NVCUVID

# opencl:
# WITH_OPENCL
# WITH_OPENCL_SVM

# AMD opencl
# WITH_OPENCLAMDFFT
# WITH_OPENCLAMDBLAS

# not yet sure:
# -D ENABLE_FAST_MATH=ON \ # since we don't sport gcc-4 anymore...
# -D WITH_VA=ON \

# what about:


#CC=/usr/bin/gcc-8 \
#CXX=/usr/bin/g++-8 \
#FC=gfortran-8 \ 
#CFLAGS="-O3 -march=native" \
#FFLAGS="march=native"  \
#BLAS=/opt/OpenBLAS/lib/libopenblas.a \
#LAPACK=/opt/OpenBLAS/lib/libopenblas.a \
#LD_LIBRARY_PATH=/opt/OpenBLAS/lib/${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} \
#NPY_BLAS_ORDER=openblas,blis \
#BLAS=openblas  \
#LAPACK=openblas \
#ATLAS=openblas \
#pip3 install \
#--no-binary :all: \
#numpy scipy numba scikit-learn


# some more
#-DCUDA_FAST_MATH=1 \ -DCUDA_NVCC_FLAGS="-D_FORCE_INLINES" \ -DENABLE_PRECOMPILED_HEADERS=OFF \ -DWITH_IPP=OFF \ -DBUILD_LIBPROTOBUF_FROM_SOURCES=ON \ -DCUDA_ARCH_NAME="Manual" \ -DCUDA_ARCH_BIN="52 60" \ -DCUDA_ARCH_PTX="60" \ -DWITH_CUBLAS=ON \ -DWITH_CUDA=ON \ -DBUILD_PERF_TESTS=OFF \ -DBUILD_TESTS=OFF \ -DWITH_GTK=OFF \ -DWITH_OPENCL=OFF \ -DBUILD_opencv_java=OFF \ -DBUILD_opencv_python2=OFF \ -DBUILD_opencv_python3=OFF \ -DBUILD_EXAMPLES=OFF \ -D WITH_OPENCL=OFF \ -D WITH_OPENCL_SVM=OFF \ -D WITH_OPENCLAMDFFT=OFF \ -D WITH_OPENCLAMDBLAS=OFF 
