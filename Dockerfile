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
FROM ubuntu:bionic as build
LABEL maintainer="Nimbix, Inc." \
      license="BSD"

# Update SERIAL_NUMBER to force rebuild of all layers (don't use cached layers)
ARG SERIAL_NUMBER
ENV SERIAL_NUMBER ${SERIAL_NUMBER:-20210104.1000}

ARG DEBIAN_FRONTEND=noninteractive

WORKDIR /usr/local/OpenFOAM
RUN apt-get -y update && \
    apt-get -y install build-essential flex bison git-core cmake zlib1g-dev libboost-system-dev libboost-thread-dev \
    libopenmpi-dev openmpi-bin gnuplot libreadline-dev libncurses-dev libxt-dev
RUN apt-get -y install libqt5x11extras5-dev libxt-dev qt5-default qttools5-dev curl

RUN git clone https://github.com/OpenFOAM/OpenFOAM-8.git
RUN git clone https://github.com/OpenFOAM/ThirdParty-8.git

# source the build environ, start build in 3rd party
RUN bash -c "source /usr/local/OpenFOAM/OpenFOAM-8/etc/bashrc && cd ThirdParty-8 && ./Allwmake"
RUN bash -c "source /usr/local/OpenFOAM/OpenFOAM-8/etc/bashrc && cd OpenFOAM-8 && ./Allwmake -j && bash ./makeParaView"

################# Multistage Build, stage 2 ###################################
FROM ubuntu:bionic
COPY --from=build /usr/local/OpenFOAM /usr/local/openfoam

ARG DEBIAN_FRONTEND=noninteractive

WORKDIR /tmp

# Install image-common tools and desktop
RUN apt-get -y update && \
    apt-get -y install wget gnupg curl software-properties-common && \
    curl -H 'Cache-Control: no-cache' \
        https://raw.githubusercontent.com/nimbix/image-common/master/install-nimbix.sh \
        | bash -s -- --setup-nimbix-desktop

#RUN apt-get -y install libopenmpi-dev openmpi-bin libqt5gui5 libqt5help5 libqt5x11extras5
RUN apt-get -y install libopenmpi-dev openmpi-bin paraview

COPY scripts /usr/local/scripts

COPY NAE/AppDef.json /etc/NAE/AppDef.json
RUN curl --fail -X POST -d @/etc/NAE/AppDef.json https://api.jarvice.com/jarvice/validate

COPY NAE/screenshot.png /etc/NAE/screenshot.png
COPY NAE/OpenFOAM-logo-135x135.png /etc/NAE/OpenFOAM-logo-135x135.png
