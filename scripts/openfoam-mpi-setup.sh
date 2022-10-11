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

# # Wait for slaves...max of 60 seconds
# SLAVE_CHECK_TIMEOUT=60
# TOOLSDIR="/usr/local/JARVICE/tools/bin"
# ${TOOLSDIR}/python_ssh_test ${SLAVE_CHECK_TIMEOUT}
# ERR=$?
# if [[ ${ERR} -gt 0 ]]; then
#   echo "One or more slaves failed to start" 1>&2
#   exit ${ERR}
# fi

# # start SSHd
# if [[ -x /usr/sbin/sshd ]]; then
#   sudo service ssh start
# fi

# Detect AWS and its EFA provider for the OFI fabric
[[ $JARVICE_MPI_PROVIDER == efa ]] && export EFA_ACTIVE=1

# Default to TCP provider if nothing else detected
[[ -z "$JARVICE_MPI_PROVIDER" ]] && JARVICE_MPI_PROVIDER=tcp || true

# Select the MPI variant
if [ "$JARVICE_MPI_CMA" != "true" ]; then
  export OMPI_MCA_btl_vader_single_copy_mechanism=none
fi

if [[ -n $EFA_ACTIVE ]]; then
  echo "INFO: using EFA for OpenMPI"
  export FI_EFA_FORK_SAFE=1
  export MPIRUN='/opt/JARVICE/openmpi/bin/mpirun'
else
  export MPIRUN='mpirun'
fi
