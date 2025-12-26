#!/usr/bin/env bash

set -e

# Get latest openfoam for testing
IMAGE=$(docker images --format table | grep openfoam | head -n1 | awk '{print $1 ":" $2}')

echo "INFO: Found $IMAGE"

# Select model to test with
# BENCH_MARK="cavity"
# BENCH_MARK="cavity-simple"
BENCH_MARK="cavity-simple-refineMesh"
NUM_CORES=$(lscpu | grep "Core(s) per socket:" | awk '{print $NF}')
NUM_CELLS=1000000

# BENCH_MARK="motorbike" # BETA TEST IMAGE! MAY NOT WORK!

docker run \
    -it \
    --rm \
    --shm-size=16g \
    ${IMAGE} /usr/bin/bash -ec "
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
