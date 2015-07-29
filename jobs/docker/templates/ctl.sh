#!/bin/bash -e

RUN_DIR=/var/vcap/sys/run/docker
LOG_DIR=/var/vcap/sys/log/docker
PIDFILE=$RUN_DIR/docker.pid

DOCKER_PKG=/var/vcap/packages/docker-1.7.1
DOCKER_DATA_DIR=/var/vcap/data/docker

TMPDIR=$DOCKER_DATA_DIR/tmp
mkdir -p $TMPDIR

case $1 in

  start)
    mkdir -p $RUN_DIR
    chown -R vcap:vcap $RUN_DIR

    mkdir -p $LOG_DIR
    chown -R vcap:vcap $RUN_DIR

    mkdir -p $DOCKER_DATA_DIR

    # mount cgroups
    $(dirname $0)/cgroups-mount

    TMPDIR=$TMPDIR exec $DOCKER_PKG/docker -d \
      -H tcp://0.0.0.0:4243 \
      -p $PIDFILE \
      -g $DOCKER_DATA_DIR \
      -mtu 1500 \
      --insecure-registry=<%= p("docker_registry.address") %> \
      1>>$LOG_DIR/docker.stdout.log \
      2>>$LOG_DIR/docker.stderr.log

    ;;

  stop)
    pkill -9 -f 'docker -d -H tcp://0.0.0.0:4243'

    ;;

  *)
    echo "Usage: ctl {start|stop}"

    ;;

esac
