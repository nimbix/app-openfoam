#!/usr/bin/env bash
# Copyright (c) 2026, Nimbix, Inc.
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

# set -e

source /usr/local/scripts/openfoam-benchmark-helper.sh

if [[ $OPENFOAM_TYPE == "ORG" ]]; then
    cp -r ${FOAM_TUTORIALS}/incompressibleFluid/motorBikeSteady/* .
else
    cp -r ${FOAM_TUTORIALS}/incompressible/simpleFoam/motorBike/* .
fi

function updateDecomposePar()
{
    echo "Updating the decomposeParDict file..."
    CASE=$1
    numProcs=$2
    numNodes=$3

    if [[ $OPENFOAM_TYPE == "ORG" ]]; then
        cp $FOAM_TUTORIALS/fluid/helmholtzResonance/system/decomposeParDict $CASE/system/. # Just a scotch
    else
        cp $FOAM_TUTORIALS/compressible/rhoPimpleFoam/laminar/helmholtzResonance/system/decomposeParDict $CASE/system/. # Just a scotch
    fi

    # Update the number of subdoamains and update the method used
    totalSubdomains=$(perl -e "print $numProcs*$numNodes")
    sed -i "s/numberOfSubdomains  4;/numberOfSubdomains  $totalSubdomains;/" $CASE/system/decomposeParDict
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

function updateControlDict()
{
    echo "Updating controlDict file"
    CASE=$1
    SCALING=$2
    WRITE_INTERVAL=$3

    # Calculate the time step needed to hit a 0.1 CFL number
    numSteps=30 # $(perl -e "print 10.0/0.005")

    sed -i "s/endTime         500;/endTime         $numSteps;/" $CASE/system/controlDict


    if [[ $WRITE_INTERVAL -gt 0 ]]; then
        sed -i "s/writeInterval   100;/writeInterval   $WRITE_INTERVAL;/" $CASE/system/controlDict
    else
        WRITE_INTERVAL=$((numSteps+1))
        sed -i "s/writeInterval   100;/writeInterval   $WRITE_INTERVAL;/" $CASE/system/controlDict
    fi
}

function updateSnappyHexMeshDict()
{
    echo "Updating the snappyHexMeshDict..."
    local CASE=$1
    local NUMBEROFCELLS=$2
    local maxGlobalCells=$(($(getNumberOfProcessors)*2))000000
    # sed -i "s/addLayers       true;/addLayers       false;/" $CASE/system/snappyHexMeshDict
    sed -i "s/    maxLocalCells 100000;/    maxLocalCells 1500000;/" $CASE/system/snappyHexMeshDict
    sed -i "s/    maxGlobalCells 2000000;/    maxGlobalCells $NUMBEROFCELLS;/" $CASE/system/snappyHexMeshDict
    # sed -i "s/    maxLoadUnbalance 0.10;/    maxLoadUnbalance 0.01;/" $CASE/system/snappyHexMeshDict
    # sed -i "s/            level (5 6);/            level (5 7);/" $CASE/system/snappyHexMeshDict
    # sed -i "s/            level   4;/            level   5;/" $CASE/system/snappyHexMeshDict
}

CASE=$1
NUM_PROCS=$2
NUM_NODES=$3
NUMBEROFCELLS=$4
INTERCONNECT=$5
WRITE_INTERVAL=$6

# SCALING=$(perl -e "print ($NUMBEROFCELLS/354538)")
SCALING=$(perl -e "print (($NUMBEROFCELLS/354538)**(1/3))")
echo ----------------------------------------------
time updateDecomposePar $CASE $NUM_PROCS $NUM_NODES
sleep 1
echo ----------------------------------------------
time updateBlockMesh $CASE $SCALING
sleep 1
echo ----------------------------------------------
time updateSnappyHexMeshDict $CASE $NUMBEROFCELLS
sleep 1
echo ----------------------------------------------
time updateControlDict $CASE $SCALING $WRITE_INTERVAL
sleep 1
echo ----------------------------------------------

if [[ $OPENFOAM_TYPE == "ORG" ]]; then
    mkdir -p "$CASE/constant/geometry/"
    cp $FOAM_TUTORIALS/resources/geometry/motorBike.obj.gz $CASE/constant/geometry/
    surfaceFeatures > log.surfaceFeatures 2>&1
else
    mkdir -p constant/triSurface
    # cp -f "$FOAM_TUTORIALS"/resources/geometry/motorBike.obj.gz $CASE/constant/triSurface/
    ## Error in motorBike.obj.gz file from the v2606 src, just use the one from github...
    cd constant/triSurface/ || exit 1
    wget https://gitlab.com/openfoam/core/openfoam/-/raw/master/tutorials/resources/geometry/motorBike.obj.gz
    cd ../..
    surfaceFeatureExtract > log.surfaceFeatures 2>&1
fi
sleep 1
time runBlockMesh $CASE
sleep 1
echo ----------------------------------------------
time runDecomposePar $CASE
sleep 1
echo ----------------------------------------------
stime=$(date '+%s%3N')
time runSnappyHexMesh $CASE $INTERCONNECT
etime=$(date '+%s%3N')
sleep 1
dt_build=$((etime-stime))
echo ----------------------------------------------
time runRenumberMesh $CASE $INTERCONNECT
sleep 1
echo ----------------------------------------------
time runCheckMesh $CASE $INTERCONNECT
sleep 1
echo ----------------------------------------------
time runPotentialFoam $CASE $INTERCONNECT
sleep 1
echo ----------------------------------------------
stime=$(date '+%s%3N')
if [[ $OPENFOAM_TYPE == "ORG" ]]; then
    time runParallelUsingInterface $CASE $INTERCONNECT foamRun
else
    time runParallelUsingInterface $CASE $INTERCONNECT simpleFoam
fi
etime=$(date '+%s%3N')
dt_solver=$((etime-stime))
echo ----------------------------------------------

NUMBER_OF_CELLS=$(grep cells\: log.checkMesh | awk {'print $2'})
MESH_BUILD_SCORE=$(perl -e "print int(86400000.0/$dt_build+0.99)")
SOLVER_SCORE=$(perl -e "print int(86400000.0/$dt_solver+0.99)")

if [[ ! -f "../benchmark.csv" ]]; then
  echo "DATE, VERSION, CPU, BENCHMARK, NUM_PROCS, NUM_NODES, SCALING, INTERCONNECT, NUMBER_OF_CELLS, WRITE_INTERVAL, BUILD_SCORE, SOLVER_SCORE" > ../benchmark.csv
fi

DATE=$(date +%F_%T)
CPU=$(lscpu | awk -F: '/Model name/ {gsub(/^[ \t]+/,"",$2); print $2}')
echo "DATE, VERSION, CPU, BENCHMARK, NUM_PROCS, NUM_NODES, SCALING, INTERCONNECT, NUMBER_OF_CELLS, WRITE_INTERVAL, BUILD_SCORE, SOLVER_SCORE"
echo "$DATE, $OPENFOAM_VERSION, $CPU, Mortor Bike, $NUM_PROCS, $NUM_NODES, $SCALING, $INTERCONNECT, $NUMBER_OF_CELLS, $WRITE_INTERVAL, $MESH_BUILD_SCORE, $SOLVER_SCORE"
echo "$DATE, $OPENFOAM_VERSION, $CPU, Mortor Bike, $NUM_PROCS, $NUM_NODES, $SCALING, $INTERCONNECT, $NUMBER_OF_CELLS, $WRITE_INTERVAL, $MESH_BUILD_SCORE, $SOLVER_SCORE" >> ../benchmark.csv
