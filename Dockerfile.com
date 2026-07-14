# Copyright (c) 2026, Nimbix, Inc.
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
ARG SERIAL_NUMBER=20250701.1000

# Load updated JARVICE MPI with UCX
FROM us-docker.pkg.dev/jarvice/images/mpi-builder:5.0.8-el9-gcc14 AS buffer

# Update SERIAL_NUMBER to force rebuild of all layers (don't use cached layers)
ARG SERIAL_NUMBER
ENV SERIAL_NUMBER=${SERIAL_NUMBER}

ARG OPENFOAM_VERSION
ENV OPENFOAM_VERSION=${OPENFOAM_VERSION}

# Enable fast mirrors
RUN echo "max_parallel_downloads=20" >> /etc/dnf/dnf.conf && \
    echo "fastestmirror=True" >> /etc/dnf/dnf.conf && \
    dnf update -y --refresh

# Add dependencies
RUN dnf install -y epel-release && \
    dnf config-manager --set-enabled crb && \
    dnf update -y && \
    dnf install -y\
        bc\
        cmake\
        diffutils\
        fftw-devel\
        flex\
        gcc-c++\
        git\
        gmp-devel\
        libffi-devel\
        m4\
        mousepad\
        mpfr-devel\
        paraview\
        perl\
        wget\
        which\
        zlib-devel\
    && dnf clean all

# Add OpenFOAM Repo (-4 -> use ipv4 -nv -> no verbose)
WORKDIR /opt/OpenFOAM
RUN curl -L https://dl.openfoam.com/source/${OPENFOAM_VERSION}/OpenFOAM-${OPENFOAM_VERSION}.tgz | tar xz
RUN curl -L https://dl.openfoam.com/source/${OPENFOAM_VERSION}/ThirdParty-${OPENFOAM_VERSION}.tar.gz | tar xz

# Add missing ThirdParty source
WORKDIR /opt/OpenFOAM/ThirdParty-${OPENFOAM_VERSION}
RUN curl -L https://sourceforge.net/projects/openfoam-extend/files/foam-extend-3.0/ThirdParty/metis-5.1.0.tar.gz/download | tar xz

# RUN cp -r /opt/OpenFOAM /opt/OpenFOAM-avx512

# Build OpenFOAM with JARVICE MPI (LOOK INTO WM_CFLAGS="-std=gnu17" to allow scotch to build)
RUN cd /opt/OpenFOAM/ && sed -i 's/\-O3\b/-O3 -mtune=generic -march=x86-64-v3/g' $(grep -lr -- "-O3" .)
SHELL ["/usr/bin/bash", "-c"]
RUN source /opt/JARVICE-MPI/jarvice_mpi.sh && \
    source /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}/etc/bashrc && \
    cd /opt/OpenFOAM/ThirdParty-${OPENFOAM_VERSION} && \
    ./Allwmake -j$(nproc) -q

RUN source /opt/JARVICE-MPI/jarvice_mpi.sh && \
    source /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}/etc/bashrc && \
    cd /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION} && \
    ./Allwmake -j$(nproc) -q && \
    ./Allwmake -j$(nproc) -q && rm -rf build && rm -rf sources

# # Build OpenFOAM with JARVICE MPI with AVX-512
# RUN cd /opt/OpenFOAM-avx512/ && sed -i 's/\-O3\b/-O3 -mtune=generic -march=x86-64-v4/g' $(grep -lr -- "-O3" .)
# SHELL ["/bin/bash", "-c"]
# RUN source /opt/JARVICE/jarvice_mpi.sh && \
#     source /opt/OpenFOAM-avx512/OpenFOAM-${OPENFOAM_VERSION}/etc/bashrc && \
#     cd /opt/OpenFOAM-avx512/ThirdParty-${OPENFOAM_VERSION} && \
#     ./Allwmake -j$(nproc) -q

# RUN source /opt/JARVICE/jarvice_mpi.sh && \
#     source /opt/OpenFOAM-avx512/OpenFOAM-${OPENFOAM_VERSION}/etc/bashrc && \
#     cd /opt/OpenFOAM-avx512/OpenFOAM-${OPENFOAM_VERSION} && \
#     ./Allwmake -j$(nproc) -q && \
#     ./Allwmake -j$(nproc) -q && rm -rf build && rm -rf sources

# Main Program
# FROM us-docker.pkg.dev/jarvice/images/mpi-test:custom-mpi-ucx-pci as JARVICE_MPI
# FROM rockylinux/rockylinux:9
FROM us-docker.pkg.dev/jarvice/images/mpi-builder:5.0.8-el9-gcc14
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
RUN dnf install -y epel-release &&\
    dnf config-manager --set-enabled crb &&\
    dnf update -y && \
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
        htop btop\
        libffi-devel\
        m4\
        mousepad\
        mpfr-devel\
        paraview\
        perl\
        vim\
        wget\
        which\
        zlib-devel\
    && dnf clean all

# Copy over files
COPY --from=buffer --chmod=0777 /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION} /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}
COPY --from=buffer --chmod=0777 /opt/OpenFOAM/ThirdParty-${OPENFOAM_VERSION}/platforms /opt/OpenFOAM/ThirdParty-${OPENFOAM_VERSION}/platforms

# COPY --from=buffer --chmod=0777 /opt/OpenFOAM-avx512/OpenFOAM-${OPENFOAM_VERSION} /opt/OpenFOAM-avx512/OpenFOAM-${OPENFOAM_VERSION}
# COPY --from=buffer --chmod=0777 /opt/OpenFOAM-avx512/ThirdParty-${OPENFOAM_VERSION}/platforms /opt/OpenFOAM-avx512/ThirdParty-${OPENFOAM_VERSION}/platforms

# Replace custom foamJob file with one provided by openfoam
COPY buildScripts/foamJob.com /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}/bin/foamJob
# COPY buildScripts/foamJob.com /opt/OpenFOAM-avx512/OpenFOAM-${OPENFOAM_VERSION}/bin/foamJob

COPY scripts /usr/local/scripts

RUN echo "OPENFOAM_VERSION=${OPENFOAM_VERSION}" >> /etc/environment

COPY NAE/screenshot.png /etc/NAE/screenshot.png
COPY NAE/license.txt /etc/NAE/license.txt
COPY NAE/OpenFOAM-logo-135x135.png /etc/NAE/OpenFOAM-logo-135x135.png

# RUN echo "" >> /etc/NAE/license.txt && cat /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}/COPYING >> /etc/NAE/license.txt
RUN echo "" >> /etc/NAE/license.txt && cat /opt/OpenFOAM/OpenFOAM-${OPENFOAM_VERSION}/LICENSE.md >> /etc/NAE/license.txt

# Copy over the app image and the AppDef
COPY NAE/AppDef-com.json /etc/NAE/AppDef.json
RUN curl --fail -X POST -d @/etc/NAE/AppDef.json https://cloud.nimbix.net/api/jarvice/validate
RUN mkdir -p /etc/NAE && touch /etc/NAE/{screenshot.png,screenshot.txt,license.txt,AppDef.json,swlicense.txt}
