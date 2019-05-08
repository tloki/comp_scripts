FROM ubuntu:18.04

WORKDIR /root

RUN apt update && apt upgrade -y

RUN apt update && apt install sudo -y

# from script - just to be quicker!
RUN apt update && apt install build-essential python3-dev python3-setuptools python3-pip make git -y

ADD ./run.sh /root/run.sh

# run compilaton for the first time, including tests

RUN bash run.sh

# add something useful here
CMD ["/bin/bash"]
