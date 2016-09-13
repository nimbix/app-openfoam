#!/bin/bash

# Configuration
# http://cfd.direct/openfoam/user-guide/running-applications-parallel/

# Usage
# http://cfd.direct/openfoam/user-guide/tutorials/

# OpenFOAM is MPI-based for invocation of most of its processes

. /opt/openfoam4/etc/bashrc

QT_GRAPHICSSYSTEM="opengl"; export QT_GRAPHICSSYSTEM

exec $@
