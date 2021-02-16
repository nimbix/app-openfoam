#!/usr/bin/env bash
# Copyright (c) 2020, Nimbix, Inc.
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

# This JARVICE batch processing script is an example of submitting multiple
# OpenFOAM processing steps in one multi-node run with MPI.
#
#  Here, we make the optional steps to implement the dam break example
#  https://cfd.direct/openfoam/user-guide/v7-dambreak/#x7-640002.3.12
#

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

set -e

# parse command line
CASE="/data/openfoam8/run"
MESHTYPE="blockMesh"
SOLVER="laplacianFoam"

while [[ -n "$1" ]]; do
  case "$1" in
  -case)
    shift
    CASE="$1"
    ;;
  -mesh)
    MESHTYPE="true"
    ;;
  -meshtype)
    shift
    MESHTYPE="$1"
    ;;
  -solver)
    shift
    SOLVER="$1"
    ;;
  *)
    echo "Invalid argument: $1" >&2
    exit 1
    ;;
  esac
  shift
done

# add override for the OpenFOAM project dir
echo "WM_PROJECT_USER_DIR=/data/openfoam" | sudo tee -a "$FOAMETC"/prefs.sh >/dev/null
export WM_PROJECT_USER_DIR=/data/openfoam

# create the working dir, the "run" dir where files go, matches to FOAM_RUN in env
mkdir -p /data/openfoam8/run

# select Case dir, strip file name off path
CASE=$(dirname "$CASE")
echo "Using OpenFOAM Case directory: $CASE"
cd "$CASE"

if [[ -f /usr/local/openfoam/OpenFoam-8/bashrc ]]; then
  echo "Sourcing OpenFOAM environment"
  source /usr/local/openfoam/OpenFoam-8/bashrc || return
else
  echo "ERROR: OpenFOAM environment unavailable"
  exit 1
fi

# decompose prepped Mesh option

# run selected mesh and log
echo "Running selected mesh and logging to $CASE/case.log"
$MESHTYPE | tee -a "$CASE"/case.log

# set initial fields
echo "Running setFields and logging to $CASE/case.log"
setFields | tee -a "$CASE"/case.log

# run solver on mesh with MPI
$SOLVER | tee -a "$CASE"/case.log

# post-process prep: reconstruct mesh
