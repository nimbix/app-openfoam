#!/usr/bin/env bash
# Copyright (c) 2024, Nimbix, Inc.
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

if [[ $OPENFOAM_TYPE == "ORG" ]]; then
    cp -r $FOAM_TUTORIALS/incompressibleFluid/cavityCoupledU/* .
else
    cp -r $FOAM_TUTORIALS/incompressible/pisoFoam/RAS/cavityCoupledU/* .
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
    NY=$(perl -e "print int($scaling*20+0.99)")
    NZ=$(perl -e "print int($scaling*20+0.99)")
    sed -i "s/    hex (0 1 2 3 4 5 6 7) (20 20 1) simpleGrading (1 1 1)/    hex (0 1 2 3 4 5 6 7) ($NX $NY $NZ) simpleGrading (1 1 1)/" $CASE/system/blockMeshDict
    sed -i "s/    (0 0 0.1)/    (0 0 1)/" $CASE/system/blockMeshDict
    sed -i "s/    (1 0 0.1)/    (1 0 1)/" $CASE/system/blockMeshDict
    sed -i "s/    (1 1 0.1)/    (1 1 1)/" $CASE/system/blockMeshDict
    sed -i "s/    (0 1 0.1)/    (0 1 1)/" $CASE/system/blockMeshDict
    sed -i "s/        type empty;/        type wall;/" $CASE/system/blockMeshDict
}

function updateBoundaryConditions()
{
    echo "Updating boundary conditions"
    CASE=$1
    # for file in $CASE/0/*; do
    #     echo "\tUpdating $file"
    # done

    sed -i "s/        type            empty;/        type            epsilonWallFunction;\\n        value           uniform 0.000765;/" $CASE/0/epsilon
    sed -i "s/        type            empty;/        type            kqRWallFunction;\\n        value           uniform 0.00325;/" $CASE/0/k
    sed -i "s/        type            empty;/        type            nutkWallFunction;\\n        value           uniform 0;/" $CASE/0/nut
    sed -i "s/        type            empty;/        type            zeroGradient;/" $CASE/0/nuTilda
    sed -i "s/        type            empty;/        type            zeroGradient;/" $CASE/0/p
    sed -i "s/        type            empty;/        type            noSlip;/" $CASE/0/U
}

function updateControlDict()
{
    echo "Updating controlDict file"
    CASE=$1
    SCALING=$2

    x=0.1
    N=$(perl -e "print int($scaling*20+0.99)")
    dx=$(perl -e "print $x/$N")

    # Calculate the time step needed to hit a 0.1 CFL number
    # CFL = u * dt/dx -> 0.1 = 1.0 * dt / dx -> dt = 0.1*1.0*dx -> dt = 0.1*dx
    dt=$(perl -e "print $dx*0.1")
    numSteps=30 # $(perl -e "print 10.0/0.005")
    endTime=$(perl -e "print $dt*$numSteps")

    sed -i "s/endTime         10;/endTime         $endTime;/" $CASE/system/controlDict
    sed -i "s/deltaT          0.005;/deltaT          $dt;/" $CASE/system/controlDict
}

function updateFvSolution()
{
    echo "Updating fvSolution file"
    CASE=$1

    # # Remove coupled velocity solver...
    sed -i "s/        type            coupled;/        \/\/ type            coupled;/" $CASE/system/fvSolution
    sed -i "s/        solver          PBiCCCG;/        solver          PBiCGStab;/" $CASE/system/fvSolution
    sed -i "s/        tolerance       (1e-05 1e-05 1e-05);/        tolerance       1e-05;/" $CASE/system/fvSolution
    sed -i "s/        relTol          (0 0 0);/        relTol          0;/" $CASE/system/fvSolution

    # Add nCellsInCoarsestLevel value to pressure (default is 10...)
    # sed -i -e '/        smoother        GaussSeidel/a\' -e '        nCellsInCoarsestLevel 200;' $CASE/system/fvSolution
    # Use FDIC + PCG
    sed -i "s/        solver          GAMG;/        solver          PCG;\\n        preconditioner  FDIC;/" $CASE/system/fvSolution

    # Change pressure solver to PCG solver          smoothSolver;
    # sed -i "/        smoother        GaussSeidel;/d" $CASE/system/fvSolution
    # sed -i "s/        solver          GAMG;/        solver          PCG;\n        preconditioner  DIC;/" $CASE/system/fvSolution


    # # Change pressure solver to PBiCGStab
    # sed -i "s/        solver          GAMG;/        solver    PBiCGStab;/" $CASE/system/fvSolution
    # sed -i "s/        smoother        GaussSeidel;/        preconditioner  DIC;/" $CASE/system/fvSolution
}

CASE=$1
NUM_PROCS=$2
NUM_NODES=$3
NUMBER_OF_CELLS=$4
INTERCONNECT=$5

# Need to calculate the scaling needed
SCALING=$(echo "e((1/3)*l(${NUMBER_OF_CELLS}))/20" | bc -l)

echo ----------------------------------------------
time updateDecomposePar $CASE $NUM_PROCS $NUM_NODES
sleep 1
echo ----------------------------------------------
time updateBlockMesh $CASE $SCALING
sleep 1
echo ----------------------------------------------
time updateBoundaryConditions $CASE
sleep 1
echo ----------------------------------------------
time updateControlDict $CASE $SCALING
sleep 1
echo ----------------------------------------------
time updateFvSolution $CASE
sleep 1
echo ----------------------------------------------
time runBlockMesh $CASE
sleep 1
echo ----------------------------------------------
echo "Running decomposePar"
time decomposePar > $CASE/log.decomposePar
sleep 1
echo ----------------------------------------------
time runRenumberMesh $CASE $INTERCONNECT
sleep 1
echo ----------------------------------------------
time runCheckMesh $CASE $INTERCONNECT
sleep 1
echo ----------------------------------------------
# time runPotentialFoam $CASE $INTERCONNECT
# echo ----------------------------------------------
echo "Running pisoFoam"
stime=$(date '+%s%3N')
if [[ $OPENFOAM_TYPE == "ORG" ]]; then
    time runParallelUsingInterface $CASE $INTERCONNECT foamRun
else
    time runParallelUsingInterface $CASE $INTERCONNECT pisoFoam
fi
etime=$(date '+%s%3N')
dt_solver=$((etime-stime))
echo ----------------------------------------------

NUMBER_OF_CELLS=$(grep cells\: log.checkMesh | awk {'print $2'})
SOLVER_SCORE=$(perl -e "print int(86400000.0/$dt_solver+0.99)")

if [[ ! -f "../benchmark.csv" ]]; then
  echo "BENCHMARK, NUM_PROCS, NUM_NODES, SCALING, INTERCONNECT, NUMBER_OF_CELLS, BUILD_SCORE, SOLVER_SCORE" > ../benchmark.csv
fi

echo "BENCHMARK, NUM_PROCS, NUM_NODES, SCALING, INTERCONNECT, NUMBER_OF_CELLS, BUILD_SCORE, SOLVER_SCORE"
echo "Cavity, $NUM_PROCS, $NUM_NODES, $SCALING, $INTERCONNECT, $NUMBER_OF_CELLS, NA, $SOLVER_SCORE"
echo "Cavity, $NUM_PROCS, $NUM_NODES, $SCALING, $INTERCONNECT, $NUMBER_OF_CELLS, NA, $SOLVER_SCORE" >> ../benchmark.csv
