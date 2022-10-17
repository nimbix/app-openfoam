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

# Load jarvice_mpi image as JARVICE_MPI
FROM us-docker.pkg.dev/jarvice/images/jarvice_mpi:4.1 as JARVICE_MPI

# Multistage to optimise, as image does not need to contain jarvice_mpi
# components, these are side loaded during job containers init.
FROM ubuntu:jammy as buffer

# Update SERIAL_NUMBER to force rebuild of all layers (don't use cached layers)
ARG SERIAL_NUMBER
ENV SERIAL_NUMBER ${SERIAL_NUMBER:-20221017.1000}

# Grab jarvice_mpi from JARVICE_MPI
COPY --from=JARVICE_MPI /opt/JARVICE /opt/JARVICE

# Add dependencies
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tzdata
RUN apt-get install -y build-essential cmake nano git ca-certificates wget
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y flex libfl-dev bison zlib1g-dev libboost-system-dev libboost-thread-dev libopenmpi-dev openmpi-bin gnuplot libreadline-dev libncurses-dev libxt-dev
RUN apt-get install -y python3-dev python3-pip git bc scotch ptscotch libfltk1.3-dev libocct-data-exchange-dev libocct-foundation-dev libocct-modeling-algorithms-dev libocct-modeling-data-dev libocct-ocaf-dev libocct-visualization-dev

# Add OpenFOAM Repo
WORKDIR /opt/OpenFOAM
RUN wget -O - http://dl.openfoam.org/source/10 | tar xz
RUN wget -O - http://dl.openfoam.org/third-party/10 | tar xz
RUN mv OpenFOAM-10-version-10 OpenFOAM-10
RUN mv ThirdParty-10-version-10 ThirdParty-10

# Add extra compile options
#   -flto for link time optimizations
RUN cd /opt/OpenFOAM/OpenFOAM-10/ && sed -i 's/\-fPIC\b/-fPIC -flto/g' $(grep -lr -- "-fPIC" wmake/.)
RUN cd /opt/OpenFOAM/OpenFOAM-10/ && sed -i 's/\-fPIC\b/-fPIC -flto/g' $(grep -lr -- "-fPIC" etc/.)

# Build OpenFOAM with JARVICE MPI
SHELL ["/bin/bash", "-c"]
RUN source /opt/JARVICE/jarvice_mpi.sh && \
    source /opt/OpenFOAM/OpenFOAM-10/etc/bashrc && \
    cd /opt/OpenFOAM/OpenFOAM-10 && \
    ./Allwmake -j24 -q

# Remove .o files and .dep files
RUN cd /opt/OpenFOAM/OpenFOAM-10 && \
    find platforms/*/applications platforms/*/src -name "*.o" | xargs rm && \
    find platforms/*/applications platforms/*/src -name "*.dep" | xargs rm

# Main Program
FROM ubuntu:jammy
LABEL maintainer="Nimbix, Inc." \
      license="BSD"

# Update SERIAL_NUMBER to force rebuild of all layers (don't use cached layers)
ARG SERIAL_NUMBER
ENV SERIAL_NUMBER ${SERIAL_NUMBER:-20221017.1000}

ARG DEBIAN_FRONTEND=noninteractive

WORKDIR /tmp

# Install image-common tools and desktop
RUN apt-get -y update && \
    DEBIAN_FRONTEND=noninteractive apt-get -y install ca-certificates curl htop --no-install-recommends && \
    curl -H 'Cache-Control: no-cache' \
        https://raw.githubusercontent.com/nimbix/jarvice-desktop/master/install-nimbix.sh \
        | bash

RUN apt-get install -y paraview scotch ptscotch

# Copy over files
COPY --from=buffer /opt/OpenFOAM/OpenFOAM-10 /opt/OpenFOAM/OpenFOAM-10
COPY --from=buffer /opt/OpenFOAM/ThirdParty-10 /opt/OpenFOAM/ThirdParty-10

# Replace custom foamJob file with one provided by openfoam
COPY buildScripts/foamJob /opt/OpenFOAM/OpenFOAM-10/bin

COPY scripts /usr/local/scripts

COPY NAE/screenshot.png /etc/NAE/screenshot.png
COPY NAE/OpenFOAM-logo-135x135.png /etc/NAE/OpenFOAM-logo-135x135.png

COPY NAE/AppDef.json /etc/NAE/AppDef.json
# RUN curl --fail -X POST -d @/etc/NAE/AppDef.json https://cloud.nimbix.net/api/jarvice/validate
