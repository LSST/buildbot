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
LAST_SUCCESSFUL_MANIFEST="lastSuccessfulBuildManifest.list"
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
    echo "                --verbose: print out extra debugging info"
    echo "                  --force: if package already installed, re-install "
    echo "       --ccdCount <count>: number of CCDs to use during run"
    echo "   --astro_data <version>: version of astrometry_net_data to use"
    echo "         --runType <type>: type of run being done; Select one of:"
    echo "                           { buildbot }; default=buildbot"
    echo "        --manifest <path>: manifest list for eups-setup."
    echo "                  --beta : flags use of beta instead of master packages."
    echo "    --builder_name <name>: buildbot's build name assigned to run"
    echo "  --build_number <number>: buildbot's build number assigned to run"
}
#--------------------------------------------------------------------------

check1() {
    if [ "$1" = "" ]; then
        usage
        exit 1
    fi
}


# Setup LSST buildbot support fnunctions
source ${0%/*}/gitBuildFunctions.sh

DEBUG=debug
DEV_SERVER="lsstdev.ncsa.uiuc.edu"
WEB_HOST="lsst-build.ncsa.illinois.edu"
WEB_ROOT="/usr/local/home/buildbot/www/"

# -------------------
# -- get arguments --
# -------------------

options=$(getopt -l verbose,debug,ccdCount:,runType:,tag:,beta,log_dest:,log_url:,builder_name:,build_number:,astro_data:,manifest: -- "$@")

BUILDER_NAME=""
BUILD_NUMBER=0
RUN_TYPE='buildbot'
CCD_COUNT=20
MANIFEST=

while true
do
    case $1 in
        --verbose)      VERBOSE=true; shift;;
        --debug)        VERBOSE=true; shift;;
        --ccdCount)     CCD_COUNT=$2;  shift 2;;
        --runType)      RUN_TYPE=$2; shift 2;;
        --beta)         USE_BETA=true; shift;;
        --tag)          TAG_LIST=$2; shift 2;;
        --builder_name) BUILDER_NAME=$2; shift 2;;
        --build_number) BUILD_NUMBER=$2; shift 2;;
        --astro_data)   ASTRO_DATA_VERSION=$2; shift 2;;
        --manifest)     MANIFEST=$2; shift 2;;
        *) echo "parsed options; arguments left are:: $* ::"
             break;;
    esac
done


if [ "$CCD_COUNT" -le 0 ]; then
    usage
    exit 1
fi

source $LSST_HOME/loadLSST.sh

eups admin clearCache -Z $LSST_DEVEL
eups admin buildCache -Z $LSST_DEVEL

#*************************************************************************
echo "CCD_COUNT: $CCD_COUNT"
echo "RUN_TYPE: $RUN_TYPE"
echo "BUILDER_NAME: $BUILDER_NAME"
echo "BUILD_NUMBER: $BUILD_NUMBER"
echo "ASTRO_DATA_VERSION: $ASTRO_DATA_VERSION"
echo "USE_BETA: $USE_BETA"
echo "MANIFEST: $MANIFEST"
#*************************************************************************

#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
# May need to revise this section if/when testing_endtoend transitions to BETA
# to select one vs the other based on $USE_BETA.
#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/

WORK_DIR=`pwd`
for PACKAGE in testing_endtoend; do
    [[ "$DEBUG" ]] && echo "/\/\/\/\/\/\/\/\/\ Extracting package: $PACKAGE /\/\/\/\/\/\/\/\/"
    [[ "$DEBUG" ]] && echo ""
    # SCM checkout ** from master **
    prepareSCMDirectory $PACKAGE BUILD
    if [ $RETVAL != 0 ]; then
        echo "Failed to extract $PACKAGE source directory during setup for runDrp.sh use."
        exit 1
    fi
    # setup all dependencies required by $PACKAGE
    cd $SCM_LOCAL_DIR
    [[ "$DEBUG" ]] && echo ""
    [[ "$DEBUG" ]] && echo "/\/\/\/\/\/\/\/\/\ Prior to $PACKAGE setup /\/\/\/\/\/\/\/"
    eups list -s
    setup -r .
    [[ "$DEBUG" ]] && echo ""
    [[ "$DEBUG" ]] && echo "/\/\/\/\/\/\/\/\/\ After $PACKAGE setup /\/\/\/\/\/\/\/"
    eups list -s
    cd $WORK_DIR
done

#1 Feb 12# # Replacing with manifest list installation
#1 Feb 12# # setup the production run packages
#1 Feb 12# if [ $USE_BETA ]; then
#1 Feb 12#     setup --tag=beta --tag=current --tag=stable datarel
#1 Feb 12#     setup -r $ASTROMETRY_NET_DATA_DIR/$ASTRO_DATA_VERSION astrometry_net_data 
#1 Feb 12# else
#1 Feb 12#     setup --tag=current --tag=stable datarel
#1 Feb 12#     setup -r $ASTROMETRY_NET_DATA_DIR/$ASTRO_DATA_VERSION astrometry_net_data  
#1 Feb 12# fi


##
# ensure full dependencies file is available
##
if [ ! -f "$LAST_SUCCESSFUL_MANIFEST" ]; then
    echo "error: Can't find $LAST_SUCCESSFUL_MANIFEST. Exiting."
    exit 1
fi

# Setup the entire build environment for a production run
while read LINE; do
    set $LINE
    echo "Setting up: $1   $2"
    setup -j $1 $2
done < $LAST_SUCCESSFUL_MANIFEST

echo " ----------------------------------------------------------------"
eups list -s
echo "-----------------------------------------------------------------"


# Explictily setup the astro data requested
setup -j -r $ASTROMETRY_NET_DATA_DIR/$ASTRO_DATA_VERSION astrometry_net_data 

echo ""
echo "/\/\/\/\/\/\/\/\/\ After  datarel setup /\/\/\/\/\/\/\/\/"
eups list  -s
eups list astrometry_net_data
echo ""

cd $TESTING_ENDTOEND_DIR
echo "Backgrounding drpRun in preparation for job process detachment"
echo "($TESTING_ENDTOEND_DIR/bin/drpRun.py --ccdCount $CCD_COUNT --runType $RUN_TYPE -m robyn@lsst.org &)"
$TESTING_ENDTOEND_DIR/bin/drpRun.py --ccdCount $CCD_COUNT --runType $RUN_TYPE -m robyn@lsst.org & 

# Enable buildbot step to return to buildslave management by
# detaching from last job
echo "Detaching from drpRun"
disown -h

echo "Exiting $0 after having disowned the drpRun process."
exit 0
