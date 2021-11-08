FROM ubuntu:18.04
WORKDIR /work
RUN apt-get update && apt-get install -y \
    iproute2 \
    iputils-ping \
    net-tools \
    iperf \
    net-tools \
  && rm -rf /var/lib/apt/lists/*
