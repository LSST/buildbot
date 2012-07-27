#! /bin/bash
# Run a production code: eg: drpRun.py

###############################################################################
###############################################################################
#       T B D     T B D     T B D    T B D    T B D    T B D
# 
# Due to the buildbot characteristic which always starts with a blank env,
# we need to collect and invoke the path info needed for a user run.
# 
# Option 1: we have the user submit a setup manifest for their personalized
# stack or we create a manifest using buildbot's HOME&DEVEL stacks.
#
# Option 2: use tags, EUPS_Path and VRO specification to define the stacks 
# to use during production runs.  (But a setup manifest is probably easier.)
#
#       T B D     T B D     T B D    T B D    T B D    T B D
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
# /lsst/home/buildbot/RHEL6/gitwork/scripts/runProduction.sh --ccdCount "4" --runType "buildbot" --lsst_home /lsst/DC3/stacks/gcc445-RH6/28nov2011 --lsst_devel /lsst/home/buildbot/RHEL6/gitwork/buildslaves/lsst-build5/TVT/sandbox --astro_data imsim-2011-08-01-0 --builder_name "Dunno" --build_number "1" --beta

#--------------------------------------------------------------------------
usage() {
#80 cols  ................................................................................
    echo "Usage: $0 [options] package"
    echo "Initiate the drpRun production validation code."
    echo
    echo "Options:"
    echo "                --verbose: print out extra debugging info"
    echo "                  --force: if package already installed, re-install "
    echo "       --ccdCount <count>: number of CCDs to use during run"
    echo "       --lsst_home <path>: path to 'stable&beta' stack 
    echo "      --lsst_devel <path>: path to 'trunk' stack 
    echo "   --astro_data <version>: version of astrometry_net_data to use"
    echo "         --runType <type>: type of run being done; Select one of:"
    echo "                           { buildbot }; default=buildbot"
# Maybe someday we'll provide one of the other
#    echo "   TBD  --manifest <path>: manifest list for eups-setup."
#    echo "   TBD  --tag <tag order>: CSV sequenced list of eups tags for package selection."
#    echo "                            default is 'trunk,beta,stable'"
     echo "                 --beta : flags use of beta instead of trunk packages."
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

options=$(getopt -l verbose,debug,ccdCount:,runType:,tag:,beta,log_dest:,log_url:,builder_name:,build_number:,lsst_home:,lsst_devel:,astro_data: -- "$@")

BUILDER_NAME=""
BUILD_NUMBER=0
RUN_TYPE='buildbot'
CCD_COUNT=20

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
        --lsst_home)    LSST_HOME=$2; shift 2;;
        --lsst_devel)   LSST_DEVEL=$2; shift 2;;
        --astro_data)   ASTRO_DATA_VERSION=$2; shift 2;;
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
echo "LSST_HOME: $LSST_HOME"
echo "LSST_DEVEL: $LSST_DEVEL"
echo "ASTRO_DATA_VERSION: $ASTRO_DATA_VERSION"
echo "USE_BETA: $USE_BETA"
#*************************************************************************

#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
# May need to revise this section if/when testing_endtoend transitions to BETA
# to select one vs the other based on $USE_BETA.
#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/

WORK_DIR=`pwd`
for PACKAGE in testing_endtoend; do
    [[ "$DEBUG" ]] && echo "/\/\/\/\/\/\/\/\/\ Extracting package: $PACKAGE /\/\/\/\/\/\/\/\/"
    [[ "$DEBUG" ]] && echo ""
    # SCM checkout ** from trunk **
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

# setup the production run packages
if [ $USE_BETA ]; then
    setup --tag=beta --tag=current --tag=stable datarel
    setup -r $ASTROMETRY_NET_DATA_DIR/$ASTRO_DATA_VERSION astrometry_net_data 
else
    setup --tag=current --tag=stable datarel
    setup -r $ASTROMETRY_NET_DATA_DIR/$ASTRO_DATA_VERSION astrometry_net_data  
fi
echo ""
echo "/\/\/\/\/\/\/\/\/\ After  datarel setup /\/\/\/\/\/\/\/\/"
eups list  -s
eups list astrometry_net_data
echo ""

cd $TESTING_ENDTOEND_DIR
echo "bin/drpRun.py --ccdCount $CCD_COUNT --runType $RUN_TYPE -m robyn@lsst.org &"
bin/drpRun.py --ccdCount $CCD_COUNT --runType $RUN_TYPE  -m robyn@lsst.org & 


echo "Exiting $0 after having backgrounded the drpRun process."
exit 0
