# Copyright (c) 2023, Nimbix, Inc.
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
ARG OPENFOAM_VERSION=v2306

# Serial Number
ARG SERIAL_NUMBER=20230730.1000

# Load jarvice_mpi image as JARVICE_MPI
FROM us-docker.pkg.dev/jarvice/images/jarvice_mpi:4.1 as JARVICE_MPI

# Multistage to optimise, as image does not need to contain jarvice_mpi
# components, these are side loaded during job containers init.
FROM ubuntu:focal as buffer

# Update SERIAL_NUMBER to force rebuild of all layers (don't use cached layers)
ARG SERIAL_NUMBER
ENV SERIAL_NUMBER=${SERIAL_NUMBER}

ARG OPENFOAM_VERSION
ENV OPENFOAM_VERSION=${OPENFOAM_VERSION}

# Grab jarvice_mpi from JARVICE_MPI
COPY --from=JARVICE_MPI /opt/JARVICE /opt/JARVICE

# Add dependencies
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        tzdata \
        cmake \
        nano \
        git \
        ca-certificates \
        wget \
        build-essential \
        flex \
        libfl-dev \
        bison \
        zlib1g-dev \
        libboost-system-dev \
        libboost-thread-dev \
        libopenmpi-dev \
        openmpi-bin \
        gnuplot \
        libreadline-dev \
        libncurses-dev \
        libxt-dev \
        libcgal-dev \
        libfftw3-dev \
        libfftw3-mpi-dev \
        python3-dev \
        python3-pip \
        git \
        bc \
        scotch \
        libscotch-dev \
        ptscotch \
        libfltk1.3-dev \
        libocct-data-exchange-dev \
        libocct-foundation-dev \
        libocct-modeling-algorithms-dev \
        libocct-modeling-data-dev \
        libocct-ocaf-dev \
        libocct-visualization-dev

# Add OpenFOAM Repo (not available yet...)
WORKDIR /opt/OpenFOAM
# RUN wget -O - https://dl.openfoam.com/source/${OPENFOAM_VERSION}/OpenFOAM-${OPENFOAM_VERSION}.tgz | tar xz
# RUN wget -O - https://dl.openfoam.com/source/${OPENFOAM_VERSION}/ThirdParty-${OPENFOAM_VERSION}.tgz | tar xz
RUN wget -O - https://develop.openfoam.com/Development/openfoam/-/archive/OpenFOAM-v2306/openfoam-OpenFOAM-v2306.tar.gz | tar xz
RUN wget -O - https://develop.openfoam.com/Development/ThirdParty-common/-/archive/v2306/ThirdParty-common-v2306.tar.gz | tar xz
RUN mv openfoam-OpenFOAM-v2306 /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}
RUN mv ThirdParty-common-v2306 /opt/OpenFOAM/ThirdParty-${OPENFOAM_VERSION}
RUN cd /opt/OpenFOAM/ThirdParty-${OPENFOAM_VERSION}; \
    wget -O - https://gforge.inria.fr/frs/download.php/file/38352/scotch_6.1.0.tar.gz | tar xz; \
    wget -O - https://github.com/KaHIP/KaHIP/archive/v3.15.tar.gz | tar xz; \
    mv KaHIP-3.15 kahip-3.15; \
    wget -O - https://sourceforge.net/projects/openfoam-extend/files/foam-extend-3.0/ThirdParty/metis-5.1.0.tar.gz/download | tar xz; \
    wget -O - https://www.fftw.org/fftw-3.3.10.tar.gz | tar xz; \
    wget -O - https://github.com/ornladios/ADIOS2/archive/refs/tags/v2.8.3.tar.gz | tar xz; \
    wget -O - https://github.com/CGAL/cgal/archive/refs/tags/releases/CGAL-4.14.3.tar.gz | tar xz; \
    wget -O - https://boostorg.jfrog.io/artifactory/main/release/1.74.0/source/boost_1_74_0.tar.gz | tar xz; \
    mv cgal-releases-CGAL-4.14.3 CGAL-4.14.3;

# Add extra compile options
#   -flto for link time optimizations
RUN cd /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}/ && sed -i 's/\-fPIC\b/-fPIC -flto/g' $(grep -lr -- "-fPIC" wmake/.)

SHELL ["/bin/bash", "-c"]
# Build OpenFOAM with JARVICE MPI
RUN source /opt/JARVICE/jarvice_mpi.sh && \
    source /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}/etc/bashrc && \
    cd /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION} && \
    ./Allwmake -j16 -q

# Remove .o files and .dep files
RUN cd /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}/build && \
    find */applications */src -name "*.o" | xargs rm && \
    find */applications */src -name "*.dep" | xargs rm

# Main Program
FROM ubuntu:focal
LABEL maintainer="Nimbix, Inc." \
      license="BSD"

# Update SERIAL_NUMBER to force rebuild of all layers (don't use cached layers)
ARG SERIAL_NUMBER
ENV SERIAL_NUMBER=${SERIAL_NUMBER}

ARG OPENFOAM_VERSION
ENV OPENFOAM_VERSION=${OPENFOAM_VERSION}

ARG DEBIAN_FRONTEND=noninteractive

WORKDIR /tmp

# Install image-common tools and desktop
RUN apt-get -y update && \
    DEBIAN_FRONTEND=noninteractive apt-get -y install ca-certificates curl --no-install-recommends && \
    curl -H 'Cache-Control: no-cache' \
        https://raw.githubusercontent.com/nimbix/jarvice-desktop/master/install-nimbix.sh \
        | bash

RUN apt-get install -y paraview scotch ptscotch mousepad bc libscotch-dev

# Copy over files
COPY --from=buffer --chmod=0777 /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION} /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}
COPY --from=buffer --chmod=0777 /opt/OpenFOAM/ThirdParty-${OPENFOAM_VERSION} /opt/OpenFOAM/ThirdParty-${OPENFOAM_VERSION}

# Replace custom foamJob file with one provided by openfoam
COPY buildScripts/foamJob.com /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}/bin/foamJob

COPY scripts /usr/local/scripts

RUN echo "OPENFOAM_VERSION=${OPENFOAM_VERSION}" >> /etc/environment

COPY NAE/screenshot.png /etc/NAE/screenshot.png
COPY NAE/OpenFOAM-logo-135x135.png /etc/NAE/OpenFOAM-logo-135x135.png

# Copy over the app image and the AppDef
COPY NAE/AppDef-com.json /etc/NAE/AppDef.json
RUN curl --fail -X POST -d @/etc/NAE/AppDef.json https://cloud.nimbix.net/api/jarvice/validate


# # # For testing locally
# # Add nimbix user
# RUN useradd --shell /bin/bash nimbix
# RUN mkdir -p /home/nimbix/
# RUN mkdir -p /data

# # Have all files be owned by nimbix user
# RUN chown -R nimbix:nimbix /home/nimbix
# RUN chown -R nimbix:nimbix /data
