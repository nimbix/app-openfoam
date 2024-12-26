#!/usr/bin/env bash

set -e

# Get latest openfoam for testing
CURRENT_OPENFOAM_IMAGE=$(podman images | grep openfoam | head -n1 | awk '{print $1 ":" $2}')

# Make a copy of the verify docker image and add the needed image
cp Dockerfile.verify Dockerfile.verify.tmp
sed -i s",CURRENT_OPENFOAM_IMAGE,$CURRENT_OPENFOAM_IMAGE," Dockerfile.verify.tmp

# Build the testing image
IMAGE="openfoam-verify:latest"
podman build --rm -f "Dockerfile.verify.tmp" -t ${IMAGE} "."

# Select model to test with
# BENCH_MARK="cavity"
BENCH_MARK="cavity-simple"
# BENCH_MARK="cavity-simple-refineMesh"
NUM_CORES=16
NUM_CELLS=900000

# BENCH_MARK="motorbike" # BETA TEST IMAGE! MAY NOT WORK!

podman run \
    -it \
    --rm \
    --shm-size=16g \
    ${IMAGE} /bin/bash -ec "
    useradd --shell /bin/bash nimbix
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
            -benchmark_case $BENCH_MARK
    '
"

rm Dockerfile.verify.tmp
podman rmi --force localhost/openfoam-verify:latest
