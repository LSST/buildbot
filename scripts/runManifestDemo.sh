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
ASTROMETRY_NET_DATA_DIR=/lsst/DC3/data/astrometry_net_data/
#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/

DEBUG=debug

# Standalone invocation for gcc master stack:
# export LSST_HOME=/lsst/DC3/stacks/gcc445-RH6/28nov2011
# export LSST_DEVEL=/lsst/home/buildbot/RHEL6//buildslaves/lsst-build1/SMBRG/sandbox
# source loadLSST.sh
# cd /lsst/home/buildbot/RHEL6//builds/SMBRG/work
# /lsst/home/buildbot/RHEL6/scripts/runManifestDemo.sh  --builder_name "Dunno" --build_number "1" --manifest /lsst/home/buildbot/RHEL6//builds/SMBRG/work/lastSuccessfulBuildManifest.list 

#--------------------------------------------------------------------------
usage() {
#80 cols  ................................................................................
    echo "Usage: $0 [options] package"
    echo "Initiate demonstration run."
    echo
    echo "Options:"
    echo "                  --debug: print out extra debugging info"
    echo "        --manifest <path>: manifest list for eups-setup."
    echo "    --builder_name <name>: buildbot's build name assigned to run"
    echo "  --build_number <number>: buildbot's build number assigned to run"
}
#--------------------------------------------------------------------------

# Setup LSST buildbot support fnunctions
source ${0%/*}/gitConstants.sh
source ${0%/*}/build_functions.sh
source ${0%/*}/gitBuildFunctions.sh

WEB_ROOT="/usr/local/home/buildbot/www/"

# -------------------
# -- get arguments --
# -------------------

options=$(getopt -l debug,builder_name:,build_number:,manifest: -- "$@")

BUILDER_NAME=""
BUILD_NUMBER=0
MANIFEST=

while true
do
    case $1 in
        --debug)        DEBUG=true; shift;;
        --builder_name) BUILDER_NAME=$2; shift 2;;
        --build_number) BUILD_NUMBER=$2; shift 2;;
        --manifest)     MANIFEST=$2; shift 2;;
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


# Acquire and Load the demo package in buildbot work directory
echo "curl -O http://dev.lsstcorp.org/cgit/contrib/demos/lsst_dm_stack_demo.git/snapshot/lsst_dm_stack_demo-Summer2012.tar.gz"
curl -O http://dev.lsstcorp.org/cgit/contrib/demos/lsst_dm_stack_demo.git/snapshot/lsst_dm_stack_demo-Summer2012.tar.gz
if [ ! -f lsst_dm_stack_demo-Summer2012.tar.gz ]; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Failed to acquire demo from: http://dev.lsstcorp.org/cgit/contrib/demos/lsst_dm_stack_demo.git/snapshot/lsst_dm_stack_demo-Summer2012.tar.gz  ."
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi

echo "tar xzf lsst_dm_stack_demo-Summer2012.tar.gz"
tar xzf lsst_dm_stack_demo-Summer2012.tar.gz
if [ $? != 0 ]; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Failed to unpack: lsst_dm_stack_demo-Summer2012.tar.gz  ."
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi

cd lsst_dm_stack_demo-Summer2012
if [ $? != 0 ]; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Failed to find unpacked directory: lsst_dm_stack_demo-Summer2012"
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

if [ -z  "$PIPE_TASKS_DIR" -o -z "$OBS_SDSS_DIR" ]; then
      echo "FAILURE: ----------------------------------------------------------"
      echo "Failed to setup either PIPE_TASKS or OBS_SDSS; both of  which are required by lsst_dm_stack_demo-Summer2012."
      echo "FAILURE: ----------------------------------------------------------"
      exit $BUILDBOT_FAILURE
fi

echo "./bin/demo.sh"
./bin/demo.sh
if [ $? != 0 ]; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Failed during execution of  lsst_dm_stack_demo-Summer2012"
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi


echo "diff detected-sources.txt.expected detected-sources.txt"
diff detected-sources.txt.expected detected-sources.txt
if  [ $? ]; then
    exit $BUILDBOT_SUCCESS
fi
exit  $BUILDBOT_WARNINGS
