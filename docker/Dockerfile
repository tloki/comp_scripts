FROM ubuntu:18.04

WORKDIR /root

RUN apt update && apt upgrade -y

RUN apt update && apt install sudo -y

# from script - just to be quicker!
RUN apt update && apt install build-essential python3-dev python3-setuptools python3-pip make gcc g++ \
git gfortran -y

ADD ./run.sh /root/run.sh

CMD ["/bin/bash", "-u", "/root/run.sh"]
