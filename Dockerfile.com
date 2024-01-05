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

# OpenFOAM Foundation, inc -> org
# OpenCFD Ltd -> com

# Openfoam Version
ARG OPENFOAM_VERSION=v2312

# Serial Number
ARG SERIAL_NUMBER=20240105.1000

# Load updated JARVICE MPI with UCX
FROM us-docker.pkg.dev/jarvice/images/mpi-test:custom-mpi-ucx as JARVICE_MPI
FROM rockylinux:9 as buffer

# Update SERIAL_NUMBER to force rebuild of all layers (don't use cached layers)
ARG SERIAL_NUMBER
ENV SERIAL_NUMBER=${SERIAL_NUMBER}

ARG OPENFOAM_VERSION
ENV OPENFOAM_VERSION=${OPENFOAM_VERSION}

# Grab jarvice_mpi from JARVICE_UCX_MPI
COPY --from=JARVICE_MPI /opt/JARVICE_UCX /opt/JARVICE_UCX

# Enable fast mirrors
RUN echo "max_parallel_downloads=20" >> /etc/dnf/dnf.conf && \
    echo "fastestmirror=True" >> /etc/dnf/dnf.conf && \
    dnf update -y --refresh

# Add dependencies
RUN dnf install -y epel-release
RUN dnf config-manager --set-enabled crb
RUN dnf update -y
RUN dnf install -y\
    bc\
    cmake\
    diffutils\
    fftw-devel\
    flex\
    gcc-c++\
    gmp-devel\
    libffi-devel\
    m4\
    mousepad\
    mpfr-devel\
    paraview\
    perl\
    wget\
    which\
    zlib-devel

# Dependencies for UCX
RUN dnf install -y\
    libpciaccess

# Add OpenFOAM Repo (-4 -> use ipv4 -nv -> no verbose)
WORKDIR /opt/OpenFOAM
RUN wget -4 -nv -O - https://dl.openfoam.com/source/${OPENFOAM_VERSION}/OpenFOAM-${OPENFOAM_VERSION}.tgz | tar xz
RUN wget -4 -nv -O - https://dl.openfoam.com/source/${OPENFOAM_VERSION}/ThirdParty-${OPENFOAM_VERSION}.tgz | tar xz

# Add missing ThirdParty source
WORKDIR /opt/OpenFOAM/ThirdParty-${OPENFOAM_VERSION}
RUN wget -4 -nv -O - https://sourceforge.net/projects/openfoam-extend/files/foam-extend-3.0/ThirdParty/metis-5.1.0.tar.gz/download | tar xz

# Build OpenFOAM with JARVICE_UCX MPI
SHELL ["/bin/bash", "-c"]
RUN JARVICE_FOLDER=/opt/JARVICE_UCX; \
    export PATH=$JARVICE_FOLDER/openmpi/bin:$JARVICE_FOLDER/bin:$PATH; \
    export LD_LIBRARY_PATH=$JARVICE_FOLDER/openmpi/lib:$JARVICE_FOLDER/lib:$LD_LIBRARY_PATH; \
    export CPATH=$JARVICE_FOLDER/openmpi/include:$JARVICE_FOLDER/include:$CPATH; \
    export MPI_HOME=$JARVICE_FOLDER/openmpi; \
    export MPI_RUN=$JARVICE_FOLDER/openmpi/bin/mpirun; \
    source /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}/etc/bashrc && \
    cd /opt/OpenFOAM/ThirdParty-${OPENFOAM_VERSION} && \
    ./Allwmake -j32 -q

RUN JARVICE_FOLDER=/opt/JARVICE_UCX; \
    export PATH=$JARVICE_FOLDER/openmpi/bin/:$JARVICE_FOLDER/bin/:$PATH; \
    export LD_LIBRARY_PATH=$JARVICE_FOLDER/openmpi/lib/:$JARVICE_FOLDER/lib/:$LD_LIBRARY_PATH; \
    export CPATH=$JARVICE_FOLDER/openmpi/include/:$JARVICE_FOLDER/include/:$CPATH; \
    export MPI_HOME=$JARVICE_FOLDER/openmpi/; \
    export MPI_RUN=$JARVICE_FOLDER/openmpi/bin/mpirun; \
    source /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}/etc/bashrc && \
    cd /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION} && \
    ./Allwmake -j32 -q && \
    ./Allwmake -j32 -q && rm -rf build

# Main Program
FROM rockylinux:9
LABEL maintainer="Nimbix, Inc." \
      license="BSD"

# Update SERIAL_NUMBER to force rebuild of all layers (don't use cached layers)
ARG SERIAL_NUMBER
ENV SERIAL_NUMBER=${SERIAL_NUMBER}

ARG OPENFOAM_VERSION
ENV OPENFOAM_VERSION=${OPENFOAM_VERSION}

RUN echo "max_parallel_downloads=20" >> /etc/dnf/dnf.conf
RUN echo "fastestmirror=True" >> /etc/dnf/dnf.conf
RUN dnf update -y --refresh

WORKDIR /tmp

# Install image-common tools and desktop
RUN dnf install -y epel-release
RUN dnf config-manager --set-enabled crb
RUN dnf update -y && \
    dnf install -y ca-certificates && \
    curl -H 'Cache-Control: no-cache' \
        https://raw.githubusercontent.com/nimbix/jarvice-desktop/master/install-nimbix.sh \
        | bash

RUN dnf install -y\
    bc\
    cmake\
    diffutils\
    fftw-devel\
    flex\
    gcc-c++\
    gmp-devel\
    libffi-devel\
    m4\
    mousepad\
    mpfr-devel\
    paraview\
    perl\
    wget\
    which\
    zlib-devel

# Dependencies for UCX
RUN dnf install -y\
    libpciaccess

# Copy over files
COPY --from=buffer --chmod=0777 /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION} /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}
COPY --from=buffer --chmod=0777 /opt/OpenFOAM/ThirdParty-${OPENFOAM_VERSION}/platforms /opt/OpenFOAM/ThirdParty-${OPENFOAM_VERSION}/platforms
COPY --from=JARVICE_MPI /opt/JARVICE_UCX /opt/JARVICE_UCX

# Replace custom foamJob file with one provided by openfoam
COPY buildScripts/foamJob.com /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}/bin/foamJob

COPY scripts /usr/local/scripts

RUN echo "OPENFOAM_VERSION=${OPENFOAM_VERSION}" >> /etc/environment

COPY NAE/screenshot.png /etc/NAE/screenshot.png
COPY NAE/OpenFOAM-logo-135x135.png /etc/NAE/OpenFOAM-logo-135x135.png

# Copy over the app image and the AppDef
COPY NAE/AppDef-com.json /etc/NAE/AppDef.json
RUN curl --fail -X POST -d @/etc/NAE/AppDef.json https://cloud.nimbix.net/api/jarvice/validate


# ################# Add user nimbix for local testing ###########################

# # Add nimbix user
# RUN useradd --shell /bin/bash nimbix
# RUN mkdir -p /home/nimbix/
# RUN mkdir -p /data

# # Have all files be owned by nimbix user
# RUN chown -R nimbix:nimbix /home/nimbix
# RUN chown -R nimbix:nimbix /data

# RUN mkdir -p /etc/JARVICE; \
#     echo "127.0.0.1" > /etc/JARVICE/cores; \
#     echo "127.0.0.1" >> /etc/JARVICE/cores; \
#     echo "127.0.0.1" >> /etc/JARVICE/cores; \
#     echo "127.0.0.1" >> /etc/JARVICE/cores; \
#     echo "127.0.0.1" >> /etc/JARVICE/cores; \
#     echo "127.0.0.1" >> /etc/JARVICE/cores; \
#     echo "127.0.0.1" >> /etc/JARVICE/cores; \
#     echo "127.0.0.1" >> /etc/JARVICE/cores; \
#     echo "127.0.0.1" >> /etc/JARVICE/cores; \
#     echo "127.0.0.1" >> /etc/JARVICE/cores; \
#     echo "127.0.0.1" >> /etc/JARVICE/cores; \
#     echo "127.0.0.1" >> /etc/JARVICE/cores; \
#     echo "127.0.0.1" >> /etc/JARVICE/cores; \
#     echo "127.0.0.1" >> /etc/JARVICE/cores; \
#     echo "127.0.0.1" >> /etc/JARVICE/cores; \
#     echo "127.0.0.1" >> /etc/JARVICE/cores

# RUN echo "127.0.0.1" > /etc/JARVICE/nodes

# # # Grab jarvice_mpi from JARVICE_MPI
# # COPY --from=JARVICE_MPI /opt/JARVICE /opt/JARVICE

# # /usr/local/scripts/openfoam-benchmark.sh -num_procs 8 -num_nodes 1 -numberOfCells 1000000 -benchmark_case cavity-simple
