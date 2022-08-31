#!/usr/bin/env bash
# Copyright (c) 2022, Nimbix, Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
# The views and conclusions contained in the software and documentation are
# those of the authors and should not be interpreted as representing official
# policies, either expressed or implied, of Nimbix, Inc.
#
# This script contains helpers for the openfoam-benchmark script

set -e

# Source the OpenFOAM bashrc file
if [[ -f /opt/openfoam10/etc/bashrc ]]; then
  echo "Sourcing OpenFOAM environment"
  source /opt/openfoam10/etc/bashrc || return
else
  echo "ERROR: OpenFOAM environment unavailable"
  exit 1
fi

# Source the runtime functions
source $WM_PROJECT_DIR/bin/tools/RunFunctions

# Needed for local testing
export OMPI_MCA_btl_vader_single_copy_mechanism=none

function updateDecomposePar()
{
    echo "Updating the decomposeParDict file..."
    CASE=$1
    numProcs=$2
    numNodes=$3

    # Update the number of subdoamains and update the method used
    totalSubdomains=$(perl -e "print $numProcs*$numNodes")
    sed -i "s/numberOfSubdomains  6;/numberOfSubdomains  $totalSubdomains;/" $CASE/system/decomposeParDict
    sed -i "s/decomposer      hierarchical;/method          scotch;/" $CASE/system/decomposeParDict
    sed -i "s/distributor     ptscotch;//" $CASE/system/decomposeParDict
}

function updateBlockMesh()
{
    echo "Updating the blockMeshDict file..."
    CASE=$1
    scaling=$2
    NX=$(perl -e "print int($scaling*20+0.99)")
    NY=$(perl -e "print int($scaling*8+0.99)")
    NZ=$(perl -e "print int($scaling*8+0.99)")
    sed -i "s/    hex (0 1 2 3 4 5 6 7) (20 8 8) simpleGrading (1 1 1)/    hex (0 1 2 3 4 5 6 7) ($NX $NY $NZ) simpleGrading (1 1 1)/" $CASE/system/blockMeshDict
}

function updateSnappyHexMeshDict()
{
    echo "Updating the snappyHexMeshDict..."
    CASE=$1
    maxGlobalCells=$(($(getNumberOfProcessors)*2))000000
    # sed -i "s/addLayers       true;/addLayers       false;/" $CASE/system/snappyHexMeshDict
    sed -i "s/    maxLocalCells 100000;/    maxLocalCells 1500000;/" $CASE/system/snappyHexMeshDict
    sed -i "s/    maxGlobalCells 2000000;/    maxGlobalCells $maxGlobalCells;/" $CASE/system/snappyHexMeshDict
    sed -i "s/    maxLoadUnbalance 0.10;/    maxLoadUnbalance 0.01;/" $CASE/system/snappyHexMeshDict
    sed -i "s/            level (5 6);/            level (5 7);/" $CASE/system/snappyHexMeshDict
    # sed -i "s/            level   4;/            level   5;/" $CASE/system/snappyHexMeshDict
}

function runBlockMesh()
{
    echo "Running blockmesh"
    CASE=$1
    cp $FOAM_TUTORIALS/resources/geometry/motorBike.obj.gz $CASE/constant/geometry/
    surfaceFeatures > log.surfaceFeatures 2>&1
    blockMesh > log.blockMesh 2>&1
}

function runDecomposePar()
{
    echo "Running decomposePar"
    CASE=$1
    decomposePar -copyZero > $CASE/log.decomposePar 2>&1
}

function runSnappyHexMesh()
{
    echo "Running snappyHexMesh"
    CASE=$1
    INTERCONNECT=$2
    runParallelUsingInterface $CASE $INTERCONNECT snappyHexMesh -overwrite
}

function runRenumberMesh()
{
    echo "Running renumberMesh"
    CASE=$1
    INTERCONNECT=$2
    runParallelUsingInterface $CASE $INTERCONNECT renumberMesh -overwrite
}

function runCheckMesh()
{
    echo "Running checkMesh"
    CASE=$1
    INTERCONNECT=$2
    runParallelUsingInterface $CASE $INTERCONNECT checkMesh
}

function runPotentialFoam()
{
    echo "Running potentialFoam"
    CASE=$1
    INTERCONNECT=$2
    runParallelUsingInterface $CASE $INTERCONNECT potentialFoam
}

function runSimpleFoam()
{
    echo "Running simpleFoam"
    CASE=$1
    INTERCONNECT=$2
    runParallelUsingInterface $CASE $INTERCONNECT simpleFoam
}

# https://nekodaemon.com/2021/02/05/Understanding-MPI-map-by-and-bind-to-option/#Appendix
function runParallelUsingInterface()
{
    CASE=$1
    shift
    INTERCONNECT=$1
    shift
    APP=$1
    shift
    NUM_PROCS=$(getNumberOfProcessors)

    if [[ $NUM_PROCS == 1 ]]; then
        $APP "$@" > $CASE/log.$APP 2>&1
    else

        mpiInterfaceOptions=""

        if [[ -f /etc/JARVICE/cores ]]; then
            # Now need to see if we are running locally...
            if [[ $(cat /etc/JARVICE/cores) == JARVICE ]]; then
                mpiHostOptions=""
            else
                mpiHostOptions="--hostfile /etc/JARVICE/nodes"
            fi
        else
            mpiHostOptions=""
        fi

        mpiSetOptions="--verbose \
        --nooversubscribe \
        --display-map \
        --display-allocation \
        --bind-to core \
        --map-by numa:PE=1 \
        --report-bindings"
        mpirun $mpiInterfaceOptions $mpiHostOptions -np $NUM_PROCS $mpiSetOptions $APP "$@" -parallel > $CASE/log.$APP 2>&1
    fi
}
