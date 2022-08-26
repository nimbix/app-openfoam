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
# This script contains helpers for the benchmark script

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

updateDecomposePar()
{
    echo "Updating the decomposeParDict file..."
    numProcs=$1
    numNodes=$2

    # Update the number of subdoamains and update the method used
    totalSubdomains=$(perl -e "print $numProcs*$numNodes")
    sed -i "s/numberOfSubdomains  6;/numberOfSubdomains  $totalSubdomains;/" /data/openfoam10/benchmark/system/decomposeParDict
    sed -i "s/decomposer      hierarchical;/method          scotch;/" /data/openfoam10/benchmark/system/decomposeParDict
    sed -i "s/distributor     ptscotch;//" /data/openfoam10/benchmark/system/decomposeParDict
}

updateBlockMesh()
{
    echo "Updating the blockMeshDict file..."
    scaling=$1
    NX=$(perl -e "print int($scaling*20+0.99)")
    NY=$(perl -e "print int($scaling*8+0.99)")
    NZ=$(perl -e "print int($scaling*8+0.99)")
    sed -i "s/    hex (0 1 2 3 4 5 6 7) (20 8 8) simpleGrading (1 1 1)/    hex (0 1 2 3 4 5 6 7) ($NX $NY $NZ) simpleGrading (1 1 1)/" /data/openfoam10/benchmark/system/blockMeshDict
}

updateSnappyHexMeshDict()
{
    echo "Updating the snappyHexMeshDict..."
    maxGlobalCells=$(($(getNumberOfProcessors)*2))000000
    sed -i "s/    maxLocalCells 100000;/    maxLocalCells 150000;/" /data/openfoam10/benchmark/system/snappyHexMeshDict
    sed -i "s/    maxGlobalCells 2000000;/    maxGlobalCells $maxGlobalCells;/" /data/openfoam10/benchmark/system/snappyHexMeshDict
    sed -i "s/    maxLoadUnbalance 0.10;/    maxLoadUnbalance 0.01;/" /data/openfoam10/benchmark/system/snappyHexMeshDict
    sed -i "s/            level (5 6);/            level (5 7);/" /data/openfoam10/benchmark/system/snappyHexMeshDict
    sed -i "s/            level   4;/            level   5;/" /data/openfoam10/benchmark/system/snappyHexMeshDict
}

runBlockMesh()
{
    echo "Running blockmesh"
    cp $FOAM_TUTORIALS/resources/geometry/motorBike.obj.gz /data/openfoam10/benchmark/constant/geometry/
    surfaceFeatures > log.surfaceFeatures
    blockMesh > log.blockMesh
}

runDecomposePar()
{
    echo "Running decomposePar"
    decomposePar -copyZero > /data/openfoam10/benchmark/log.decomposePar
}

runSnappyHexMesh()
{
    echo "Running snappyHexMesh"
    INTERCONNECT=$1
    runParallelUsingInterface $INTERCONNECT snappyHexMesh -overwrite
}

runPotentialFoam()
{
    echo "Running potentialFoam"
    INTERCONNECT=$1
    runParallelUsingInterface $INTERCONNECT potentialFoam
}

runSimpleFoam()
{
    echo "Running simpleFoam"
    INTERCONNECT=$1
    runParallelUsingInterface $INTERCONNECT simpleFoam
}

runParallelUsingInterface()
{
    INTERCONNECT=$1
    shift
    APP=$1
    shift
    NUM_PROCS=$(getNumberOfProcessors)
    mpirun -np $NUM_PROCS $APP "$@" -parallel > /data/openfoam10/benchmark/log.$APP 2>&1
}
