#! /bin/bash
# Run a production code: eg: drpRun.py

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

#Standalone invocation:
# source loadLSST.sh
# /lsst/home/buildbot/RHEL6/gitwork/scripts/runManifestProduction.sh --ccdCount "4" --runType "buildbot" --astro_data imsim-2011-08-01-0 --builder_name "Dunno" --build_number "1" --beta

#--------------------------------------------------------------------------
usage() {
#80 cols  ................................................................................
    echo "Usage: $0 [options] package"
    echo "Initiate requested production code then detach control."
    echo
    echo "Options:"
    echo "                --debug: print out extra debugging info"
    echo "       --ccdCount <count>: number of CCDs to use during run"
    echo "         --runType <type>: type of run being done; Select one of:"
    echo "                           { buildbot }; default=buildbot"
    echo "   --astro_data <version>: version of astrometry_net_data to use"
    echo "      --input_data <name>: name of input data set"
    echo "        --manifest <path>: manifest list for eups-setup."
    echo "                  --beta : flags use of beta instead of master packages."
    echo "    --builder_name <name>: buildbot's build name assigned to run"
    echo "  --build_number <number>: buildbot's build number assigned to run"
}
#--------------------------------------------------------------------------

# Setup LSST buildbot support fnunctions
source ${0%/*}/gitConstants.sh
source ${0%/*}/build_functions.sh
source ${0%/*}/gitBuildFunctions.sh


# -------------------
# -- get arguments --
# -------------------

options=$(getopt -l debug,ccdCount:,runType:,beta,builder_name:,build_number:,astro_net_data:,input_data:,manifest: -- "$@")

BUILDER_NAME=""
BUILD_NUMBER=0
RUN_TYPE='buildbot'
CCD_COUNT=20
MANIFEST=

while true
do
    case $1 in
        --debug)        DEBUG=true; shift;;
        --ccdCount)     CCD_COUNT=$2;  shift 2;;
        --runType)      RUN_TYPE=$2; shift 2;;
        --beta)         USE_BETA=true; shift;;
        --builder_name) BUILDER_NAME=$2; shift 2;;
        --build_number) BUILD_NUMBER=$2; shift 2;;
        --astro_net_data)   ASTRO_NET_DATA_VERSION=$2; shift 2;;
        --input_data)   INPUT_DATA=$2; shift 2;;
        --manifest)     MANIFEST=$2; shift 2;;
        *) [ "$*" != "" ] && echo "parsed options; arguments left are:$*:"
             break;;
    esac
done


if [ "$CCD_COUNT" -le 0 ]; then
    echo "FAILURE: -----------------------------------------------------------"
    usage
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi

source $LSST_HOME/loadLSST.sh

eups admin clearCache -Z $LSST_DEVEL
eups admin buildCache -Z $LSST_DEVEL

#*************************************************************************
echo "CCD_COUNT: $CCD_COUNT"
echo "RUN_TYPE: $RUN_TYPE"
echo "BUILDER_NAME: $BUILDER_NAME"
echo "BUILD_NUMBER: $BUILD_NUMBER"
echo "ASTRO_NET_DATA_VERSION: $ASTRO_NET_DATA_VERSION"
echo "INPUT_DATA: $INPUT_DATA"
echo "USE_BETA: $USE_BETA"
echo "MANIFEST: $MANIFEST"
echo "Current `umask -p`"
#*************************************************************************

WORK_DIR=`pwd`

##
# ensure full dependencies file is available
##
if [ ! -e $MANIFEST ] || [ "`cat $MANIFEST | wc -l`" = "0" ]; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Failed to find file: $MANIFEST, in buildbot work directory."
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi

# Block for current release circa 20120725 which doesn't have pipe_tasks
if [ "`grep pipe_tasks $MANIFEST`" = "" ]; then
    echo "WARNING: -----------------------------------------------------------"
    echo "No pipe_tasks package in: $MANIFEST; not running drpRun ."
    echo "WARNING: -----------------------------------------------------------"
    exit $BUILDBOT_WARNINGS
fi

# Block is for ctrl_orca which fails in stacks for v5_2 & release/Summer2012
if [ "$BUILDER_NAME" = "v5_2_Run_Rh6_Gcc" ]  || \
   [ "$BUILDER_NAME" = "v5_2_Run_Rh6_Clg" ] || \
   [ "$BUILDER_NAME" = "Git_releases_Summer2012_Run_Rh6_Gcc" ] || \
   [ "$BUILDER_NAME" = "Git_releases_Summer2012_Run_Rh6_Clg" ] || \
   [ "$BUILDER_NAME" = "releases_Summer2012_Run_Rh6_Gcc" ] || \
   [ "$BUILDER_NAME" = "releases_Summer2012_Run_Rh6_Clg" ] ; then
    echo "WARNING: -----------------------------------------------------------"
    echo "Not running drpRun for v5_2 nor releases/Summer2012  builds til testing_endtoend updated for those manifests. 24 Jul 2012"
    echo "WARNING: -----------------------------------------------------------"
    exit $BUILDBOT_WARNINGS
fi

# Setup the entire build environment for a production run
while read LINE; do
    set $LINE
    echo "Setting up: $1   $2"
    setup -j $1 $2
done < $MANIFEST

# Explicitly setup the astro data requested
setup -j -r $ASTROMETRY_NET_DATA_DIR/$ASTRO_NET_DATA_VERSION astrometry_net_data 

echo ""
echo " ----------------------------------------------------------------"
eups list  -s
echo "-----------------------------------------------------------------"
echo ""
echo "Current `umask -p`"

cd $TESTING_ENDTOEND_DIR
# raa 8Mar2012 - don't detach
#echo "(umask 002;$TESTING_ENDTOEND_DIR/bin/drpRun.py --ccdCount $CCD_COUNT --runType $RUN_TYPE --input $INPUT_DATA  <&- > $WORK_DIR/setup/build$BUILD_NUMBER/drpRun.log 2>&1 &)&"
#(umask 002; $TESTING_ENDTOEND_DIR/bin/drpRun.py --ccdCount $CCD_COUNT --runType $RUN_TYPE --input $INPUT_DATA  <&- > $WORK_DIR/setup/build$BUILD_NUMBER/drpRun.log 2>&1 &)& 
#
#echo "Exiting $0 after detaching drpRun process and reassigning I/O streams to log: $WORK_DIR/setup/build$BUILD_NUMBER/drpRun.log ."


if [ "`uname -n`" != "lsst9.ncsa.illinois.edu" ] ; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "FAILURE: Not testing production run  until drpRun slave on lsst9**"
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_WARNINGS
fi


echo "$TESTING_ENDTOEND_DIR/bin/drpRun.py --ccdCount $CCD_COUNT -m $BUCK_STOPS_HERE --testOnly"
$TESTING_ENDTOEND_DIR/bin/drpRun.py --ccdCount $CCD_COUNT -m $BUCK_STOPS_HERE --testOnly

RUN_STATUS=$?
echo "Exiting $0 after drpRun; run status: $RUN_STATUS ."
if  [ $RUN_STATUS = 0 ]; then
    exit $BUILDBOT_SUCCESS
fi
exit  $BUILDBOT_FAILURE
