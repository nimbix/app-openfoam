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
# This script runs the motorbike steady-state example at differing sizes and
# MPI interfaces.

# Source the JARVICE job environment variables
[[ -r /etc/JARVICE/jobenv.sh ]] && source /etc/JARVICE/jobenv.sh

# Wait for slaves...max of 60 seconds
SLAVE_CHECK_TIMEOUT=60
TOOLSDIR="/usr/local/JARVICE/tools/bin"
${TOOLSDIR}/python_ssh_test ${SLAVE_CHECK_TIMEOUT}
ERR=$?
if [[ ${ERR} -gt 0 ]]; then
  echo "One or more slaves failed to start" 1>&2
  exit ${ERR}
fi

# start SSHd
if [[ -x /usr/sbin/sshd ]]; then
  sudo service ssh start
fi

# OpenFOAM config dir
FOAMETC=/opt/openfoam10/etc

# Add in the OpenFOAM environment to each node and override for the OpenFOAM project dir
if [[ $(cat /etc/JARVICE/cores) != JARVICE ]]; then
  for i in $(cat /etc/JARVICE/nodes); do
    ssh $i echo "WM_PROJECT_USER_DIR=/data/openfoam10" | sudo tee -a "$FOAMETC"/prefs.sh >/dev/null
    ssh $i 'sed -i "1 i\source /opt/openfoam10/etc/bashrc" $HOME/.bashrc'
    ssh $i 'sed -i "1 i\export OMPI_MCA_btl_vader_single_copy_mechanism=none" $HOME/.bashrc' # May not be needed
  done
fi

set -e

# parse command line
NUM_PROCS="16"
NUM_NODES="1"
SCALING="1"
INTERCONNECT='ib'

while [[ -n "$1" ]]; do
  case "$1" in
  -num_procs)
    shift
    NUM_PROCS="$1"
    ;;
    -num_nodes)
    shift
    NUM_NODES="$1"
    ;;
  -scaling)
    shift
    SCALING="$1"
    ;;
  -interconnect)
    shift
    INTERCONNECT="$1"
    ;;
  *)
    echo "Invalid argument: $1" >&2
    exit 1
    ;;
  esac
  shift
done

# Copy the motorbike tutorial to working directory
CASE="/data/openfoam10/benchmark"
if [[ -d "$CASE" ]]; then
  rm -r $CASE
fi
mkdir -p $CASE
cd $CASE
source /usr/local/scripts/openfoam-benchmark-helper.sh
cp -r /opt/openfoam10/tutorials/incompressible/simpleFoam/motorBike/* .

echo ----------------------------------------------
time updateDecomposePar $CASE $NUM_PROCS $NUM_NODES
echo ----------------------------------------------
time updateBlockMesh $CASE $SCALING
echo ----------------------------------------------
time updateSnappyHexMeshDict $CASE
echo ----------------------------------------------
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
  echo "NUM_PROCS, NUM_NODES, SCALING, INTERCONNECT, NUMBER_OF_CELLS, BUILD_SCORE, SOLVER_SCORE" > ../benchmark.csv
fi

# Show potentialfoam in terminal
cat $CASE/log.potentialFoam

echo "NUM_PROCS, NUM_NODES, SCALING, INTERCONNECT, NUMBER_OF_CELLS, BUILD_SCORE, SOLVER_SCORE"
echo "$NUM_PROCS, $NUM_NODES, $SCALING, $INTERCONNECT, $NUMBER_OF_CELLS, $MESH_BUILD_SCORE, $SOLVER_SCORE"
echo "$NUM_PROCS, $NUM_NODES, $SCALING, $INTERCONNECT, $NUMBER_OF_CELLS, $MESH_BUILD_SCORE, $SOLVER_SCORE" >> ../benchmark.csv
