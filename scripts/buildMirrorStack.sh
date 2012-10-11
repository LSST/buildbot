#!/bin/bash
#
# buildMirrorStack  --config <file> [--id=<id>]
#
# Given a config.sh file, that must at least define the paths STACK_FROM and
# STACK_TO, rebuild all packages present in STACK_FROM in STACK_TO
#
# This script is most commonly used to rebuild all packages using a
# different compiler (or compiler settings)
#
# The [--id <id>] is an identifier appended to all files that this script generates
# (e.g., logs), and defaults to current time if not given.
#


source ${0%/*}/gitConstants.sh

#--------------------------------------------------------------------------
usage() {
#80 cols  ................................................................................
    echo "Usage: $0 --config <file> [--id <string>]"
    echo "Mirror a DM code stack with tags using provided configuration file."
    echo
    echo "Options:"
    echo "                  --debug: print out extra debugging info"
    echo "          --config <path>: configuration file for mirror's build."
    echo "           --id <string> : append string to mirror's stack name."
    echo "                           Default is current date."
    echo "    --builder_name <name>: buildbot's build name assigned to run"
    echo "  --build_number <number>: buildbot's build number assigned to run"
}
#--------------------------------------------------------------------------
echo "Entering buildMirrorStack: $* "

WORK_DIR=`pwd`

# EUPS needs this
export SHELL=${SHELL:-/bin/bash}
# 'sort -i' doesn't know how to sort unless LANG is set
export LANG="en_US.UTF-8"


# -------------------
# -- get arguments --
# -------------------

options=$(getopt -l debug,builder_name:,build_number:,config:,id: -- "$@")


unset ID CONFIG
BUILDER_NAME=""
BUILD_NUMBER=0

while true
do
    case $1 in
        --debug)        DEBUG=true; shift;;
        --builder_name) BUILDER_NAME=$2; shift 2;;
        --build_number) BUILD_NUMBER=$2; shift 2;;
        --config)       CONFIG=$2; shift 2;;
        --id)           ID=$2; shift 2;;
        *) [ "$*" != "" ] && echo "parsed options; arguments left are:$*:"
             break;;
    esac
done

echo "CONFIG: $CONFIG  ID: $ID"

if [ ! -f $CONFIG ]; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Missing configuration file. \n"
    usage
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi

if [ -z $ID ]; then
    ID=$(date '+%F-%T')
fi
echo "ID: $ID"


AUTOBUILD_DIR=`pwd`

# Source the config file. Expect this will define something like:
#
# STACK_FROM="/lsst/DC3/stacks/gcc445-RH6/default/"
# STACK_TO="/lsst/DC3/stacks/clang-30-RH6/"
#
# You can also override LOGDIR, EXCEPTIONS, FAILED and BLACKLIST
# EXCEPTIONS="/somewhere/configuration/exceptions.txt"
# FAILED="/somewhere/configuration/failed.txt"
# LOGDIR="/somewhere/somearchive/logs"
# BLACKLIST=(ctrl_events ctrl_sched ctrl_orca datarel testing_endtoend)

. $CONFIG || {
    echo "FAILURE: -----------------------------------------------------------"
    echo "Error sourcing $AUTOBUILD_DIR/$CONFIG configuration file. Aborting."
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
}
echo "STACK_TO $STACK_TO STACK_FROM: $STACK_FROM"
[ -z "$BLACKLIST" ]  && BLACKLIST=()
[ -z "$LOGDIR" ]     && LOGDIR="$AUTOBUILD_DIR/logs"

# tack on $EXCEPTIONS contents into the buildbot 'work' directory
if [ ! -z "$EXCEPTIONS" ] && [ ! "$EXCEPTIONS" -ef "$AUTOBUILD_DIR/exceptions.txt" ]; then
    cat $EXCEPTIONS >> $AUTOBUILD_DIR/exceptions.txt
    sort -u $AUTOBUILD_DIR/exceptions.txt -o $AUTOBUILD_DIR/exceptions.txt
fi
EXCEPTIONS="$AUTOBUILD_DIR/exceptions.txt"

# $FAILED is not concatenated with existing stack's failures; buildbot notifies
# the list and BB Guru adds 'good' failures onto config dir's FAILED list.
if [ ! -z "$FAILED" ] && [ ! "$FAILED" -ef "$AUTOBUILD_DIR/failed.txt" ]; then
    cat $FAILED > $AUTOBUILD_DIR/failed.txt
    sort -u $AUTOBUILD_DIR/failed.txt -o $AUTOBUILD_DIR/failed.txt
fi
FAILED="$AUTOBUILD_DIR/failed.txt"

if [ ! -d $STACK_FROM ]; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Error input STACK_FROM: $STACK_FROM does not exist."
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi
if [ ! -f $STACK_FROM/loadLSST.sh ]; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Error input STACK_FROM: $STACK_FROM is missing its loadLSST.sh."
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi

if [ ! -d $STACK_TO ]; then
    echo "The output STACK_TO: STACK_TO does not exist. It will now be installed."
    unset LSST_HOME LSST_DEVEL EUPS_PATH 
    httpget=`/usr/bin/which curl` 
    if [ $? -ne 0 -o -z "$httpget" ]; then
        echo "FAILURE: --------------------------------------------------------"
        echo "Failed to find 'curl'  in order to download newinstall.sh script."
        echo "FAILURE: --------------------------------------------------------"
        exit $BUILDBOT_FAILURE
    fi
    mkdir -p $STACK_TO
    cd $STACK_TO
    curl -O http://$SW_SERVER/newinstall.sh
    bash newinstall.sh
    cd $AUTOBUILD_DIR
fi
if [ ! -f $STACK_TO/loadLSST.sh ] ; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Error: output STACK_TO: $STACK_TO is missing its loadLSST.sh." 
    echo "       remove the partial stack installation directory and then rerun."
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi

#####################

LIST_FROM=$(mktemp /tmp/buildbot_FROM_$ID.XXXXXXXXXX)
LIST_TO=$(mktemp /tmp/buildbot_TO_$ID.XXXXXXXXXX)
LOG=$(mktemp /tmp/buildbot_LOG_$ID.XXXXXXXXXX)
FAILEDNEW=$(mktemp /tmp/buildbot_FAILED_$ID.XXXXXXXXXX)

#trap "rm -f '$LIST_FROM' '$LIST_TO' '$LOG' '$FAILEDNEW' " EXIT

unset LSST_HOME EUPS_PATH LSST_DEVEL

# Equivalent of 'eups list', but guarantees that tags are sorted (case insensitive sort)
# and that all words on a line are separated by exactly one whitespace
#
eups_list() {
        eups list | sed -r 's/[ \t]+/ /g' | sort | while read l; do
                arr=($l)
                tags=($(printf '%s\n' "${arr[@]:2}" | sort -i))
                echo ${arr[0]} ${arr[1]} ${tags[@]}
        done
}
cat_list() {
        test ! -f  "$1" && return
        cat $1 | sed -r 's/[ \t]+/ /g' | sort | while read l; do
                arr=($l)
                tags=($(printf '%s\n' "${arr[@]:2}" | sort -i))
                echo ${arr[0]} ${arr[1]} ${tags[@]}
        done
}

# Test if a string is in a bash array
#
in_array() {
        local hay needle=$1
        shift
        for hay; do
                [[ $hay == $needle ]] && return 0
        done
        return 1
}

# Get list of GCC-compiled packages minus the 'setup' flags.
(
. $STACK_FROM/loadLSST.sh
eups_list  | sed -r 's/ setup/ /' > $LIST_FROM
)

# Get list of packages in the destination stack. Add exceptions and failed
# packages, so we don't attempt to build them. Remove all 'setup' flags.
. $STACK_TO/loadLSST.sh
eups_list > $LIST_TO
test -f "$EXCEPTIONS" && ( cat_list $EXCEPTIONS )  >> $LIST_TO
test -f "$FAILED"     && ( cat_list $FAILED )  >> $LIST_TO
cat $LIST_TO | sed -r 's/ setup/ /' | sort -u -o $LIST_TO

echo "====================================================="
echo "List of entries to be processed"
comm -1 -3 $LIST_TO $LIST_FROM
echo "====================================================="
# Loop through all differences
comm -1 -3 $LIST_TO $LIST_FROM | \
while read l; do
        echo "==PROCESSING: $l"
        arr=($l);
        prod=${arr[0]}
        vers=${arr[1]};

        #
        # If only the tags need updating
        #
        if eups list -q "$prod" "$vers" >/dev/null 2>&1; then
                echo "===== TAGGING: $l"
                #echo -n "clang: "; eups list "$prod" "$vers"
                #echo "g++: $l"
                # Remove existing tags
                tags=($(eups list "$prod" "$vers"))
                for tag in ${tags[@]:1}; do
                        [ "$tag" = "setup" ] && continue
                        eups undeclare --nolocks -t "$tag" "$prod" "$vers"
                done

                # Set new tags
                tags=($l)
                for tag in ${tags[@]:2}; do
                        # 'setup' looks like a tag but is a flag.
                        [ "$tag" = "setup" ] && continue
                        eups declare --nolocks -t "$tag" "$prod" "$vers"
                done
                continue
        fi

        PRODLOGDIR="$LOGDIR/$prod/$vers"
        mkdir -p "$PRODLOGDIR"

        if in_array $prod "${BLACKLIST[@]}"; then
                echo "***** Marking $prod $vers as failed (explicit rule)." | tee "$PRODLOGDIR/autobuild.log.$ID"
                echo "$l" >> $FAILEDNEW
                continue
        fi

        echo "===== INSTALLING: $prod $vers"

        if eups distrib install --nolocks $prod $vers > $LOG 2>&1; then
                echo "===== OK."
        else
                (
                        cd "$PRODLOGDIR"
                        chmod go+r "$LOG"
                        mv "$LOG" "eups_distrib.log.$ID"
                        BUILDLOG=$(tac eups_distrib.log.$ID | sed -r -n 's|lssteupsbuild.sh: scons install failed; see (/.*/build.log) for details|\1|p' | head -n 1)
                        test ! -z "$BUILDLOG" && cp $BUILDLOG "$(basename $BUILD LOG).$ID"
                        echo "***** Error building $prod $vers [ see $PRODLOGDIR/*.$ID ]"
                )
                echo "$l" >> $FAILEDNEW
                eups distrib clean --nolocks "$prod" "$vers"
        fi
done

test -s "$FAILEDNEW" && cat $FAILEDNEW >> $FAILED && sort -u $FAILED -o $FAILED


if [ -s $FAILEDNEW ]; then
    echo "Following packages attempted but failed building in the mirror stack."
    cat $FAILEDNEW
    echo "WARNING: -----------------------------------------------------------"
    echo "Failed to successfully build all packages in the mirrored stack build."
    echo "WARNING: -----------------------------------------------------------"
    exit $BUILDBOT_WARNINGS
fi

echo "Completed buildMirrorStack."
exit $BUILDBOT_SUCCESS

