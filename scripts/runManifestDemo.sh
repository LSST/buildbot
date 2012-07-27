#! /bin/bash
# Run the demo code to test DM algorithms

###############################################################################
###############################################################################
# 
# Due to the buildbot characteristic which always starts with a blank env,
# we need to collect and invoke the path info needed for a user run.
# 
# This script uses a Manifest list to setup the run environment
#
###############################################################################
###############################################################################


#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
# GLOBALS to be sourced from SRPs globals header - when ready
#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
SCM_SERVER="git.lsstcorp.org"
ASTROMETRY_NET_DATA_DIR=/lsst/DC3/data/astrometry_net_data/
#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/

DEBUG=debug

# Standalone invocation for master stack:
# export LSST_HOME=/lsst/DC3/stacks/gcc445-RH6/28nov2011
# export LSST_DEVEL=/lsst/home/buildbot/RHEL6//buildslaves/lsst-build1/SMBRG/sandbox
# source loadLSST.sh
# /lsst/home/buildbot/RHEL6/scripts/runManifestDemo.sh  --builder_name "Dunno" --build_number "1" --manifest /lsst/home/buildbot/RHEL6//builds/SMBRG/work/lastSuccessfulBuildManifest.list --demo_dir /lsst3/lsst_dm_stack_demo-Summer2012

#--------------------------------------------------------------------------
usage() {
#80 cols  ................................................................................
    echo "Usage: $0 [options] package"
    echo "Initiate demonstration run."
    echo
    echo "Options:"
    echo "                --debug: print out extra debugging info"
    echo "        --manifest <path>: manifest list for eups-setup."
    echo "        --demo_dir <path>: path to self-contained demo data and program."
    echo "    --builder_name <name>: buildbot's build name assigned to run"
    echo "  --build_number <number>: buildbot's build number assigned to run"
}
#--------------------------------------------------------------------------

# Setup LSST buildbot support fnunctions
source ${0%/*}/gitConstants.sh
source ${0%/*}/build_functions.sh
source ${0%/*}/gitBuildFunctions.sh

DEV_SERVER="lsstdev.ncsa.uiuc.edu"
WEB_HOST="lsst-build.ncsa.illinois.edu"
WEB_ROOT="/usr/local/home/buildbot/www/"

# -------------------
# -- get arguments --
# -------------------

options=$(getopt -l debug,builder_name:,build_number:,manifest:,demo_dir: -- "$@")

BUILDER_NAME=""
BUILD_NUMBER=0
RUN_TYPE='buildbot'
CCD_COUNT=20
MANIFEST=
DEMO_RUN_DIR=

while true
do
    case $1 in
        --debug)        DEBUG=true; shift;;
        --builder_name) BUILDER_NAME=$2; shift 2;;
        --build_number) BUILD_NUMBER=$2; shift 2;;
        --manifest)     MANIFEST=$2; shift 2;;
        --demo_dir)     DEMO_RUN_DIR=$2; shift 2;;
        *) [ "$*" != "" ] && echo "parsed options; arguments left are:$*:"
             break;;
    esac
done


source $LSST_HOME/loadLSST.sh

eups admin clearCache -Z $LSST_DEVEL
eups admin buildCache -Z $LSST_DEVEL

#*************************************************************************
echo "BUILDER_NAME: $BUILDER_NAME"
echo "BUILD_NUMBER: $BUILD_NUMBER"
echo "MANIFEST: $MANIFEST"
echo "DEMO_RUN_DIR: $DEMO_RUN_DIR"
echo "Current `umask -p`"
#*************************************************************************

WORK_DIR=`pwd`

##
# ensure full dependencies file is available
##
if [ ! -e $MANIFEST ] || [ "`cat $MANIFEST | wc -l`" = "0" ]; then
    usage
    echo "FAILURE: -----------------------------------------------------------"
    echo "Failed to find file: $MANIFEST, in buildbot work directory."
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi

if [ "$DEMO_RUN_DIR" = "" ] || [ ! -d $DEMO_RUN_DIR ]; then
    usage
    echo "FAILURE: -----------------------------------------------------------"
    echo "Failed to acquire input parameter: demo_dir."
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi

# Setup the entire build environment for a demo run
while read LINE; do
    set $LINE
    echo "Setting up: $1   $2"
    setup -j $1 $2
done < $MANIFEST

echo ""
echo " ----------------------------------------------------------------"
eups list  -s
echo "-----------------------------------------------------------------"
echo ""
echo "Current `umask -p`"

if [ "$PIPE_TASKS_DIR" = "" ]; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Failed to setup package: pipe_tasks which is required by demo run."
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi

echo "$DEMO_RUN_DIR/bin/demo.sh"
$DEMO_RUN_DIR/bin/demo.sh

RUN_STATUS=$?
echo "Exiting $0 after demoRun; run status: $RUN_STATUS ."
if  [ $RUN_STATUS = 0 ]; then
    exit $BUILDBOT_SUCCESS
fi
exit  $BUILDBOT_FAILURE
