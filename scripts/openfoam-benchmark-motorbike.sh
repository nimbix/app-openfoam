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

source /usr/local/scripts/openfoam-benchmark-helper.sh
cp -r ${FOAM_TUTORIALS}/incompressible/simpleFoam/motorBike/* .

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
    # sed -i "s/    maxLoadUnbalance 0.10;/    maxLoadUnbalance 0.01;/" $CASE/system/snappyHexMeshDict
    # sed -i "s/            level (5 6);/            level (5 7);/" $CASE/system/snappyHexMeshDict
    # sed -i "s/            level   4;/            level   5;/" $CASE/system/snappyHexMeshDict
}

CASE=$1
NUM_PROCS=$2
NUM_NODES=$3
SCALING=$4
INTERCONNECT=$5
echo ----------------------------------------------
time updateDecomposePar $CASE $NUM_PROCS $NUM_NODES
echo ----------------------------------------------
time updateBlockMesh $CASE $SCALING
echo ----------------------------------------------
time updateSnappyHexMeshDict $CASE
echo ----------------------------------------------
cp $FOAM_TUTORIALS/resources/geometry/motorBike.obj.gz $CASE/constant/geometry/
surfaceFeatures > log.surfaceFeatures 2>&1
time runBlockMesh $CASE
echo ----------------------------------------------
time runDecomposePar $CASE
echo ----------------------------------------------
stime=$(date '+%s%3N')
time runSnappyHexMesh $CASE $INTERCONNECT
etime=$(date '+%s%3N')
dt_build=$((etime-stime))
echo ----------------------------------------------
time runRenumberMesh $CASE $INTERCONNECT
echo ----------------------------------------------
time runCheckMesh $CASE $INTERCONNECT
echo ----------------------------------------------
time runPotentialFoam $CASE $INTERCONNECT
echo ----------------------------------------------
stime=$(date '+%s%3N')
time runSimpleFoam $CASE $INTERCONNECT
etime=$(date '+%s%3N')
dt_solver=$((etime-stime))
echo ----------------------------------------------

NUMBER_OF_CELLS=$(grep cells\: log.checkMesh | awk {'print $2'})
MESH_BUILD_SCORE=$(perl -e "print int(86400000.0/$dt_build+0.99)")
SOLVER_SCORE=$(perl -e "print int(86400000.0/$dt_solver+0.99)")

if [[ ! -f "../benchmark.csv" ]]; then
  echo "BENCHMARK, NUM_PROCS, NUM_NODES, SCALING, INTERCONNECT, NUMBER_OF_CELLS, BUILD_SCORE, SOLVER_SCORE" > ../benchmark.csv
fi

echo "BENCHMARK, NUM_PROCS, NUM_NODES, SCALING, INTERCONNECT, NUMBER_OF_CELLS, BUILD_SCORE, SOLVER_SCORE"
echo "Mortor Bike, $NUM_PROCS, $NUM_NODES, $SCALING, $INTERCONNECT, $NUMBER_OF_CELLS, $MESH_BUILD_SCORE, $SOLVER_SCORE"
echo "Mortor Bike, $NUM_PROCS, $NUM_NODES, $SCALING, $INTERCONNECT, $NUMBER_OF_CELLS, $MESH_BUILD_SCORE, $SOLVER_SCORE" >> ../benchmark.csv
