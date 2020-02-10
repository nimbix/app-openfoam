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

# OpenFOAM config dir
FOAMETC=/opt/openfoam7/etc

# add override for the OpenFOAM project dir
echo "WM_PROJECT_USER_DIR=/data/openfoam7" | sudo tee -a "$FOAMETC"/prefs.sh >/dev/null

# Add in the OpenFOAM environment
if [[ -d $FOAMETC ]]; then
  echo ". $FOAMETC/bashrc" >> $HOME/.bashrc
  echo "cd /data/openfoam7/run" >> $HOME/.bashrc
fi
# create the working dir, the "run" dir where files go, matches to FOAM_RUN in env
mkdir -p /data/openfoam7/run

# Add a desktop shortcut for the paraFoam viewer
mkdir -p $HOME/Desktop
cp /usr/local/scripts/paraFoam.desktop $HOME/Desktop/paraFoam.desktop

# unclear if this should be set
#QT_GRAPHICSSYSTEM="opengl"; export QT_GRAPHICSSYSTEM

exec /usr/local/bin/nimbix_desktop xfce4-terminal -T OpenFOAM
