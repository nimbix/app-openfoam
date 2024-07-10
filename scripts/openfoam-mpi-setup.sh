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
# This script runs the motorbike steady-state example at differing sizes and
# MPI interfaces.

# Source the JARVICE job environment variables
[[ -r /etc/JARVICE/jobenv.sh ]] && source /etc/JARVICE/jobenv.sh
[[ -r /etc/JARVICE/jobinfo.sh ]] && source /etc/JARVICE/jobinfo.sh

TOOLSDIR="/usr/local/JARVICE/tools/bin"

# Detect AWS and its EFA provider for the OFI fabric
[[ $JARVICE_MPI_PROVIDER == efa ]] && export EFA_ACTIVE=1

# Default to TCP provider if nothing else detected
[[ -z "$JARVICE_MPI_PROVIDER" ]] && JARVICE_MPI_PROVIDER=tcp || true

# Select the MPI variant
if [ "$JARVICE_MPI_CMA" != "true" ]; then
  export OMPI_MCA_btl_vader_single_copy_mechanism=none
fi

# Get MPI
# This can be at two different places until ucx is adopted into init

# First, check if JARVICE has been updated with the ucx changes
if [[ -f /opt/JARVICE/bin/ucx_info ]]; then
  echo "INFO: Found OpenMPI at /opt/JARVICE"
  JARVICE_FOLDER=/opt/JARVICE
  export PATH=$JARVICE_FOLDER/openmpi/bin/:$JARVICE_FOLDER/bin/:$PATH
  export LD_LIBRARY_PATH=$JARVICE_FOLDER/openmpi/lib/:$JARVICE_FOLDER/lib/:$LD_LIBRARY_PATH
  export CPATH=$JARVICE_FOLDER/openmpi/include/:$JARVICE_FOLDER/include/:$CPATH
  export MPI_HOME=$JARVICE_FOLDER/openmpi/
  export MPI_RUN=$JARVICE_FOLDER/openmpi/bin/mpirun
  export MPI_HAS_UCX=true

# Now check if ucx is in JARVICE_UCX
elif [[ -f /opt/JARVICE_UCX/bin/ucx_info ]]; then
  echo "INFO: Found OpenMPI at /opt/JARVICE_UCX"
  JARVICE_FOLDER=/opt/JARVICE_UCX
  export PATH=$JARVICE_FOLDER/openmpi/bin/:$JARVICE_FOLDER/bin/:$PATH
  export LD_LIBRARY_PATH=$JARVICE_FOLDER/openmpi/lib/:$JARVICE_FOLDER/lib/:$LD_LIBRARY_PATH
  export CPATH=$JARVICE_FOLDER/openmpi/include/:$JARVICE_FOLDER/include/:$CPATH
  export MPI_HOME=$JARVICE_FOLDER/openmpi/
  export MPI_RUN=$JARVICE_FOLDER/openmpi/bin/mpirun
  export MPI_HAS_UCX=true

# If ucx is not available, use non-ucx JARVICE
elif [[ -f /opt/JARVICE/bin/fi_info ]]; then
  echo "WARNING: Did not find UCX build, using /opt/JARVICE"
  JARVICE_FOLDER=/opt/JARVICE
  export PATH=$JARVICE_FOLDER/openmpi/bin/:$JARVICE_FOLDER/bin/:$PATH
  export LD_LIBRARY_PATH=$JARVICE_FOLDER/openmpi/lib/:$JARVICE_FOLDER/lib/:$LD_LIBRARY_PATH
  export CPATH=$JARVICE_FOLDER/openmpi/include/:$JARVICE_FOLDER/include/:$CPATH
  export MPI_HOME=$JARVICE_FOLDER/openmpi/
  export MPI_RUN=$JARVICE_FOLDER/openmpi/bin/mpirun

else
  echo "WARNING: Did not find OpenMPI build, defaulting to system, this may not work..."
  export MPIRUN='mpirun'
  NO_ACC_MPI_FOUND="true"
fi

# OpenFOAM config dir
export FOAMETC=/opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}/etc
# Add in the OpenFOAM environment to each node and override for the OpenFOAM project dir
for i in $(cat /etc/JARVICE/nodes); do
  if [[ $i = "127.0.0.1" ]]; then
    continue
  fi
  if [[ -z $NO_ACC_MPI_FOUND ]]; then
    ssh $i "echo \"export PATH=$PATH\" >> $HOME/.bashrc"
    ssh $i "echo \"export LD_LIBRARY_PATH=$LD_LIBRARY_PATH\" >> $HOME/.bashrc"
    ssh $i "echo \"export CPATH=$CPATH\" >> $HOME/.bashrc"
    ssh $i "echo \"export MPI_HOME=$MPI_HOME\" >> $HOME/.bashrc"
    ssh $i "echo \"export MPI_RUN=$MPI_RUN\" >> $HOME/.bashrc"
  fi
  ssh $i "echo \"source /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}/etc/bashrc\" >> $HOME/.bashrc"
done
