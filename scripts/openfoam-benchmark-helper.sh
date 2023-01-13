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
if [[ -f /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}/etc/bashrc ]]; then
  echo "Sourcing OpenFOAM environment"
  source /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}/etc/bashrc || return
else
  echo "ERROR: OpenFOAM environment unavailable"
  exit 1
fi

# Source the runtime functions
source $WM_PROJECT_DIR/bin/tools/RunFunctions

function runBlockMesh()
{
    echo "Running blockmesh"
    CASE=$1
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
    runParallelUsingInterface $CASE $INTERCONNECT renumberMesh
}

function runCheckMesh()
{
    echo "Running checkMesh"
    CASE=$1
    INTERCONNECT=$2
    runParallelUsingInterface $CASE $INTERCONNECT checkMesh -latestTime
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

    foamJob -p -w -m $MPIRUN $APP "$@"
    cp log $CASE/log.$APP
}
