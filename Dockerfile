FROM ubuntu:latest
RUN apt-get update -y && apt-get install -y git
RUN mkdir -p /build-env
ADD . /build-env/
RUN chmod -R 600 /build-env && chmod +x /build-env/build.sh

WORKDIR /build-env/

