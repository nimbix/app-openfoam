#!/bin/bash
#------------------------------------------------------------------------------
# =========                 |
# \\      /  F ield         | OpenFOAM: The Open Source CFD Toolbox
#  \\    /   O peration     |
#   \\  /    A nd           | www.openfoam.com
#    \\/     M anipulation  |
#------------------------------------------------------------------------------
#     Copyright (C) 2011-2015 OpenFOAM Foundation
#     Copyright (C) 2019-2022 OpenCFD Ltd.
#------------------------------------------------------------------------------
# License
#     This file is part of OpenFOAM, distributed under GPL-3.0-or-later.
#
# Script
#     foamJob
#
# Description
#     Run an OpenFOAM job in background.
#     Redirects the output to 'log' in the case directory.
#
#------------------------------------------------------------------------------
# If dispatching via foamExec
foamExec="$WM_PROJECT_DIR/bin/tools/foamExec"

usage() {
    exec 1>&2
    while [ "$#" -ge 1 ]; do echo "$1"; shift; done
    cat<<USAGE

Usage: ${0##*/} [OPTION] <application> ...
options:
  -case <dir>       specify alternative case directory, default is the cwd
  -parallel         run in parallel (with mpirun)
  -screen           also send output to screen
  -append           append to existing log file instead of overwriting it
  -log=FILE         specify the log file
  -log-app          Use log.{appName} for the log file
  -no-check         run without fewer checks (eg, processor dirs etc)
  -no-log           run without log file
  -wait             wait for execution to complete (when not using -screen)
  -help             print the usage

Run an OpenFOAM job in background, redirecting output to a 'log' file
in the case directory

USAGE
    exit 1
}

#------------------------------------------------------------------------------
# Parse options

logFile="log"
optCheck=true
unset optParallel optScreen optWait logMode mpiRunCmd
mpiRunCmd="not set"
while [ "$#" -gt 0 ]
do
    case "$1" in
    -h | -help*)
        usage
        ;;
    -case)
        [ "$#" -ge 2 ] || usage "'$1' option requires an argument"
        cd "$2" 2>/dev/null || usage "directory does not exist: '$2'"
        shift
        ;;
    -p | -parallel)
        optParallel=true
        ;;
    -s | -screen)
        optScreen=true
        ;;
    -a | -append)
        logMode=append
        ;;
    -w | -wait)
        optWait=true
        ;;
    -no-check*)
        unset optCheck
        ;;
    -no-log)
        logMode=none
        logFile=log     # Consistency if -append toggles it back on
        ;;
    -log=*)
        logFile="${1##*=}"
        [ -n "$logFile" ] || logFile="log"
        ;;
    -log-app)
        logFile="{LOG_APPNAME}"  # Tag for log.appName output
        ;;
    -version=*)
        echo "Ignoring version option" 1>&2
        ;;
    -v | -version)
        [ "$#" -ge 2 ] || usage "'$1' option requires an argument"
        echo "Ignoring version option" 1>&2
        shift
        ;;
    -m | -mpiRunCmd)
        mpiRunCmd="$2"
        shift
        ;;
    --)
        shift
        break
       ;;
    -*)
        usage "invalid option '$1'"
        ;;
    *)
        break
        ;;
    esac
    shift
done

# ------------------------------------------------------------------------------

[ "$#" -ge 1 ] || usage "No application specified"

# The requested application
appName="$1"

# Does application even exist?
APPLICATION="$(command -v "$appName")" || \
    usage "Application '$appName' not found"

if [ "$logFile" = "{LOG_APPNAME}" ]
then
    logFile="log.${appName##*/}"
fi


# Need foamExec for remote (parallel) runs
if [ "$optParallel" = true ]
then

    # Use Find to get location
    # foamExec="$WM_PROJECT_DIR/bin/tools/foamExec"
    # foamExec=$(find /opt/OpenFOAM/OpenFOAM-10/bin -name foamExec)
    foamExec=$(find $WM_PROJECT_DIR -name foamExec)

    # Use foamExec for dispatching
    [ -x "$foamExec" ] || usage "File not found: $foamExec"

    APPLICATION="$foamExec"


    # # com placement
    # foamExec="$WM_PROJECT_DIR/bin/tools/foamExec"

    # # org placement
    # foamExec="$WM_PROJECT_DIR/bin/foamExec"
else
    # Drop first argument in favour of fully qualified APPLICATION
    shift
fi


# Stringify args, adding single quotes for args with spaces
echoArgs()
{
    unset stringifiedArgs

    for stringItem in "$@"
    do
        case "$stringItem" in (*' '*) stringItem="'$stringItem'" ;; esac
        stringifiedArgs="${stringifiedArgs}${stringifiedArgs:+ }${stringItem}"
    done
    echo "$stringifiedArgs"
}


if [ "$optParallel" = true ]
then
    #
    # Parallel
    #
    dict="system/decomposeParDict"

    [ -r "$dict" ] || {
        echo "No $dict found, which is required for parallel running."
        exit 1
    }

    nProcs="$(foamDictionary -entry numberOfSubdomains -value $dict 2>/dev/null)"

    # Check if case is decomposed
    if [ "$optCheck" = true ]
    then
        if [ "$(find . -maxdepth 1 \( -name 'processor0' -o -name 'processors*' \) -type d | wc -l)" -eq 0 ]
        then
            echo "Case is not currently decomposed"
            echo "Try decomposing first with \"foamJob decomposePar\""
            exit 1
        fi
    fi

    #
    # Find mpirun
    #
    if [ "$mpiRunCmd" = "not set" ]; then
        mpirun=$(command -v mpirun) || usage "'mpirun' not found"
    else
        mpirun=$(command -v $mpiRunCmd) || usage "${mpiRunCmd} not found"
    fi
    mpiopts="-n $nProcs"

    # Check if the machine ready to run parallel
    case "$WM_MPLIB" in
    *OPENMPI*)
        # Add hostfile info
        for hostfile in \
            hostfile \
            machines \
            system/hostfile \
            system/machines \
            /etc/JARVICE/nodes \
            ;
        do
            if [ -r "$hostfile" ]
            then
                mpiopts="$mpiopts -hostfile $hostfile"
                break
            fi
        done

        # Send FOAM_SETTINGS to parallel processes, so that the proper
        # definitions are sent as well.
        if [ -n "$FOAM_SETTINGS" ]
        then
            mpiopts="$mpiopts -x FOAM_SETTINGS"
        fi

        #
        # Add map-by node to options for load balancing
        #
        mpiopts="$mpiopts --map-by node"

        #
        # Add EFA specific settings here
        #

        if [ "$JARVICE_MPI_PROVIDER" == "efa" ]; then
            mpirun="/opt/JARVICE/openmpi/bin/mpirun"
            # mpiopts="$mpiopts -x FI_EFA_FORK_SAFE=1"
            # mpiopts="$mpiopts -x FI_PROVIDER=\"efa\"" # --mca btl tcp,self" # --bind-to none"
            # mpiopts="$mpiopts --mca btl tcp,vader,self --bind-to none --mca btl_tcp_if_exclude lo,docker0"
            mpiopts="$mpiopts --mca pml cm --mca mtl ofi"
        fi

        if [ "$JARVICE_MPI_PROVIDER" = "verbs" ]; then
            mpirun="/opt/JARVICE/openmpi/bin/mpirun"
            mpiopts="$mpiopts --mca btl openib,vader,self --mca btl_openib_allow_ib true"
        fi
        ;;
    esac

    #
    # Run (in parallel)
    #
    echo "Application : $appName ($nProcs processes)"
    if [ "$logMode" != "none" ]
    then
    echo "Output      : $logFile"
    fi
    echo "Executing   : $mpirun $mpiopts $APPLICATION $(echoArgs "$@") -parallel"
    if [ "$optScreen" = true ]
    then
        case "$logMode" in
        none)
            "$mpirun" $mpiopts "$APPLICATION" "$@" -parallel
            ;;
        append)
            "$mpirun" $mpiopts "$APPLICATION" "$@" -parallel | tee -a "$logFile"
            ;;
        *)
            "$mpirun" $mpiopts "$APPLICATION" "$@" -parallel | tee "$logFile"
            ;;
        esac
    else
        case "$logMode" in
        none)
            "$mpirun" $mpiopts "$APPLICATION" "$@" -parallel > /dev/null 2>&1 &
            ;;
        append)
            "$mpirun" $mpiopts "$APPLICATION" "$@" -parallel >> "$logFile" 2>&1 &
            ;;
        *)
            "$mpirun" $mpiopts "$APPLICATION" "$@" -parallel > "$logFile" 2>&1 &
            ;;
        esac

        pid=$!
        if [ "$optWait" = true ]
        then
            echo "Waiting for process $pid to finish"
            wait "$pid"
            echo "Process $pid finished"
        else
            echo "Process id  : $pid"
        fi
    fi

else
    #
    # Serial
    #
    echo "Application : $appName ($nProcs processes)"
    if [ "$logMode" != "none" ]
    then
    echo "Output      : $logFile"
    fi
    echo "Executing   : $APPLICATION $(echoArgs "$@")"
    if [ "$optScreen" = true ]
    then
        case "$logMode" in
        none)
            "$APPLICATION" "$@" &
            ;;
        append)
            "$APPLICATION" "$@" | tee -a "$logFile" &
            ;;
        *)
            "$APPLICATION" "$@" | tee "$logFile" &
            ;;
        esac

        pid=$!
        echo "Process id  : $pid"
        wait "$pid"
    else
        case "$logMode" in
        none)
            "$APPLICATION" "$@" > /dev/null 2>&1 &
            ;;
        append)
            "$APPLICATION" "$@" >> "$logFile" 2>&1 &
            ;;
        *)
            "$APPLICATION" "$@" > "$logFile" 2>&1 &
            ;;
        esac

        pid=$!
        if [ "$optWait" = true ]
        then
            echo "Waiting for process $pid to finish"
            wait "$pid"
            echo "Process $pid finished"
        else
            echo "Process id  : $pid"
        fi
    fi
fi


#------------------------------------------------------------------------------