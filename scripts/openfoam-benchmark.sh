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
[[ -r /etc/JARVICE/jobinfo.sh ]] && source /etc/JARVICE/jobinfo.sh

source /usr/local/scripts/openfoam-mpi-setup.sh

set -e

# parse command line
NUM_PROCS="0"
NUM_NODES="0"
NUMBEROFCELLS="8000"
INTERCONNECT='ib'
BENCHMARK_CASE='cavity'
KEEP_RESULTS='false'

while [[ -n "$1" ]]; do
  case "$1" in
  -num_procs)
    shift
    if [[ $1 == "0" ]]; then
      # Need to get all available cores per node -> AllCORES / ALLNODES
      NUMNODES=$(cat /etc/JARVICE/nodes | wc -l)
      NUMCORES=$(cat /etc/JARVICE/cores | wc -l)
      NUM_PROCS=$((NUMCORES/NUMNODES))
    else
      NUM_PROCS="$1"
    fi
    ;;
  -num_nodes)
    shift
    if [[ $1 == "0" ]]; then
      # Need to get all available nodes
      NUM_NODES=$(cat /etc/JARVICE/nodes | wc -l)
    else
      NUM_NODES="$1"
    fi
    ;;
  -numberOfCells)
    shift
    NUMBEROFCELLS="$1"
    ;;
  -interconnect)
    shift
    INTERCONNECT="$1"
    ;;
  -benchmark_case)
    shift
    BENCHMARK_CASE="$1"
    ;;
  -keepResults)
    KEEP_RESULTS='true'
    ;;
  *)
    echo "Invalid argument: $1" >&2
    exit 1
    ;;
  esac
  shift
done

# Copy the motorbike tutorial to working directory
[[ -z "$JOB_NAME" ]] && JOB_NAME="local" || true
CASE="/data/openfoam-${OPENFOAM_VERSION}/benchmark-${JOB_NAME}"
if [[ -d "$CASE" ]]; then
  rm -r $CASE
fi
STARTING_DIRECTORY=${PWD}
mkdir -p $CASE
cd $CASE

touch $CASE/CFD.foam
[[ "$JOB_NAME" == "local" ]] && echo "127.0.0.1" > hostfile || true

if [[ $BENCHMARK_CASE == 'motorbike' ]]; then
  exec /usr/local/scripts/openfoam-benchmark-motorbike.sh $CASE $NUM_PROCS $NUM_NODES $NUMBEROFCELLS $INTERCONNECT
elif [[ $BENCHMARK_CASE == 'cavity' ]]; then
  exec /usr/local/scripts/openfoam-benchmark-cavity.sh $CASE $NUM_PROCS $NUM_NODES $NUMBEROFCELLS $INTERCONNECT
elif [[ $BENCHMARK_CASE == 'cavity-simple' ]]; then
  exec /usr/local/scripts/openfoam-benchmark-cavity-simple.sh $CASE $NUM_PROCS $NUM_NODES $NUMBEROFCELLS $INTERCONNECT
fi

if [[ ${KEEP_RESULTS} == 'false' ]]; then
  cd ${STARTING_DIRECTORY}
  rm -r $CASE
fi
