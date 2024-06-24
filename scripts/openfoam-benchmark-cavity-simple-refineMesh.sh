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
    numSteps=30 # $(perl -e "print 10.0/0.005")

    sed -i "s/endTime         10;/endTime         ${numSteps};/" $CASE/system/controlDict
    sed -i "s/deltaT          0.005;/deltaT          1;/" $CASE/system/controlDict
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

    # Use FDIC + PCG
    sed -i "s/        solver          GAMG;/        solver          PCG;\\n        preconditioner  FDIC;/" $CASE/system/fvSolution

    # Use DILUPBiCGStab instead of smoothSolver
    sed -i "s/        solver          smoothSolver;/        solver          PBiCGStab;\\n        preconditioner  DILU;/" $CASE/system/fvSolution

    if [[ $OPENFOAM_TYPE == "ORG" ]]; then
        # Switch from PISO to SIMPLE
        sed -i "s/PIMPLE/SIMPLE/" $CASE/system/fvSolution
        sed -i "s/    nCorrectors     2;/    nCorrectors     1;/" $CASE/system/fvSolution
    else
        # Switch from PISO to SIMPLE
        sed -i "s/PISO/SIMPLE/" $CASE/system/fvSolution
    fi

    # Add consistent yes after nNonOrthogonalCorrectors
    sed -i "s/    nNonOrthogonalCorrectors 0;/    nNonOrthogonalCorrectors 0;\n    consistent yes;/" $CASE/system/fvSolution

    # Add relaxation factors to the end of the file
    echo "relaxationFactors" >> $CASE/system/fvSolution
    echo "{" >> $CASE/system/fvSolution
    echo "    p                   0.3;" >> $CASE/system/fvSolution
    echo "    equations" >> $CASE/system/fvSolution
    echo "    {" >> $CASE/system/fvSolution
    echo "        U               0.9;" >> $CASE/system/fvSolution
    echo "        k               0.7;" >> $CASE/system/fvSolution
    echo "        epsilon         0.7;" >> $CASE/system/fvSolution
    echo "    }" >> $CASE/system/fvSolution
    echo "}" >> $CASE/system/fvSolution


    # Update fvSchemes
    if [[ $OPENFOAM_TYPE == "ORG" ]]; then
        sed -i "s/    default         Euler;/    default         steadyState;/" $CASE/system/fvSchemes
    fi
}

CASE=$1
NUM_PROCS=$2
NUM_NODES=$3
NUMBER_OF_CELLS=$4
INTERCONNECT=$5

# Need to calculate the scaling needed
SCALING=$(echo "e((1/3)*l(${NUMBER_OF_CELLS}/4096))/20" | bc -l)

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
time runRefineMesh $CASE $INTERCONNECT
sleep 1
echo ----------------------------------------------
time runRefineMesh $CASE $INTERCONNECT
sleep 1
echo ----------------------------------------------
time runRefineMesh $CASE $INTERCONNECT
sleep 1
echo ----------------------------------------------
time runRefineMesh $CASE $INTERCONNECT
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
echo "Running simpleFoam"
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
SOLVER_SCORE=$(perl -e "print int(86400000.0/$dt_solver+0.99)")

# Update the scaling value
SCALING=$(echo "e((1/3)*l(${NUMBER_OF_CELLS}))/20" | bc -l)

if [[ ! -f "../benchmark.csv" ]]; then
  echo "BENCHMARK, NUM_PROCS, NUM_NODES, SCALING, INTERCONNECT, NUMBER_OF_CELLS, BUILD_SCORE, SOLVER_SCORE" > ../benchmark.csv
fi

echo "BENCHMARK, NUM_PROCS, NUM_NODES, SCALING, INTERCONNECT, NUMBER_OF_CELLS, BUILD_SCORE, SOLVER_SCORE"
echo "Cavity Simple, $NUM_PROCS, $NUM_NODES, $SCALING, $INTERCONNECT, $NUMBER_OF_CELLS, NA, $SOLVER_SCORE"
echo "Cavity Simple, $NUM_PROCS, $NUM_NODES, $SCALING, $INTERCONNECT, $NUMBER_OF_CELLS, NA, $SOLVER_SCORE" >> ../benchmark.csv
