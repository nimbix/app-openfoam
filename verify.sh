#!/usr/bin/env bash

OPENFOAM_VERSION="$1"
IMAGE=$(docker images | grep "openfoam:$OPENFOAM_VERSION" | tail -n1 | awk '{print $1}')

echo "INFO: Found $IMAGE"

# Select model to test with
# BENCH_MARK="cavity"
# BENCH_MARK="cavity-simple"
# BENCH_MARK="cavity-simple-refineMesh"
# BENCH_MARK="motorbike"
NUM_CORES=$(lscpu | grep "Core(s) per socket:" | awk '{print $NF}')
NUM_CELLS=100000

# BENCH_MARK="motorbike" # BETA TEST IMAGE! MAY NOT WORK!
RESULTS=""
for BENCH_MARK in notABenchmark cavity cavity-simple cavity-simple-refineMesh motorbike; do
    docker run \
        -it \
        --rm \
        --shm-size=16g \
        -v $PWD:/mydata:Z \
        ${IMAGE} /usr/bin/bash -ec "
        cp -rf /mydata/scripts/* /usr/local/scripts/.
        useradd --shell /usr/bin/bash nimbix
        mkdir -p /home/nimbix/
        mkdir -p /data
        chown -R nimbix:nimbix /home/nimbix
        chown -R nimbix:nimbix /data
        mkdir -p /etc/JARVICE
        echo 127.0.0.1 > /etc/JARVICE/cores
        for k in {2..$NUM_CORES}; do
            echo 127.0.0.1 >> /etc/JARVICE/cores
        done
        echo 127.0.0.1 > /etc/JARVICE/nodes
        chown -R nimbix:nimbix /etc/JARVICE
        su nimbix -c '
            cd \$HOME
            /usr/local/scripts/openfoam-benchmark.sh \
                -num_procs $NUM_CORES -num_nodes 0 \
                -numberOfCells $NUM_CELLS \
                -interconnect ib \
                -benchmark_case $BENCH_MARK \
                -writeInterval 5
        '
    "
    RESULTS+="$BENCH_MARK -> $?\n"
done
echo "Results for $IMAGE"
echo -en "$RESULTS"
