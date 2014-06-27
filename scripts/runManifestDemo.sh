#! /bin/bash
# Run the demo code to test DM algorithms

###############################################################################
###############################################################################
# 
# Due to the buildbot characteristic which always starts with a blank env,
# we need to collect and invoke the path info needed for a user run.
# 
###############################################################################
###############################################################################

#                  T B D         T B D            T B D
# Implementation will accept an eups tag to build with a specific manifest
# If not provided, use the latest master-only build
#         What is correct method to determine latest master-only build?


#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
ASTROMETRY_NET_DATA_DIR=/lsst/DC3/data/astrometry_net_data/
BB_ANCESTRAL_HOME="/lsst/home/buildbot"
#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/

DEBUG=debug

#--------------------------------------------------------------------------
# Standalone invocation for gcc master stack:
#--------------------------------------------------------------------------
# First: setup lsstsw stack
# cd $lsstsw/build
# /lsst/home/buildbot/RHEL6/scripts/runManifestDemo.sh  --builder_name "Dunno" --build_number "1" 

#--------------------------------------------------------------------------
usage() {
#80 cols  ................................................................................
    echo "Usage: $0 [options]"
    echo "Initiate demonstration run."
    echo
    echo "Options:"
    echo "                  --debug: print out extra debugging info"
    echo "        --tag <id>       : eups-tag for eups-setup."
    echo "    --builder_name <name>: buildbot's build name assigned to run"
    echo "  --build_number <number>: buildbot's build number assigned to run"
    echo "--log_dest <buildbot@host:remotepath>: scp destination_path"
    echo "          --log_url <url>: URL for web-access to the build logs "
    echo "       --step_name <name>: assigned step name in build"
}
#--------------------------------------------------------------------------

# Setup LSST buildbot support fnunctions
source ${0%/*}/gitConstants.sh
#source ${0%/*}/build_functions.sh
#source ${0%/*}/gitBuildFunctions.sh

# -------------------
# -- get arguments --
# -------------------

options=$(getopt -l debug,builder_name:,build_number:,tag:,log_dest:,log_url:,step_name: -- "$@")

BUILDER_NAME=""
BUILD_NUMBER=0
LOG_DEST=""
LOG_URL=""
STEP_NAME=""
TAG=""

while true
do
    case $1 in
        --debug)        DEBUG=true; shift;;
        --tag)          TAG=$2; shift 2;;
        --builder_name) BUILDER_NAME=$2; shift 2;;
        --build_number) BUILD_NUMBER=$2; shift 2;;
        --step_name)    STEP_NAME=$2; shift 2;;
        --log_url)      LOG_URL=$2; shift 2;;
        --log_dest)     LOG_DEST=$2;
                        LOG_DEST_HOST=${LOG_DEST%%\:*}; # buildbot@master
                        LOG_DEST_DIR=${LOG_DEST##*\:};  # /var/www/html/logs
                        shift 2;;
        *) [ "$*" != "" ] && echo "parsed options; arguments left are:$*:"
             break;;
    esac
done


#*************************************************************************
echo "EUPS-tag: $TAG"
echo "BUILDER_NAME: $BUILDER_NAME"
echo "BUILD_NUMBER: $BUILD_NUMBER"
#echo "LOG_DEST: $LOG_DEST"
#echo "LOG_URL: $LOG_URL"
echo "Current `umask -p`"
#*************************************************************************
cd ~lsstsw2/build
WORK_DIR=`pwd`

# Setup either requested tag or, lacking tag, last successfully built version
if [ -n "$TAG" ]; then
    setup -t $TAG lsst_distrib 
else
    setup -j lsst_distrib
    cd $LSST_DISTRIB_DIR/../
    VERSION=`ls | sort -r -n -t+ +1 -2 | head -1`
    setup lsst_distrib $VERSION
fi


cd $WORK_DIR

echo ""
echo " ----------------------------------------------------------------"
echo "Setup lsst_distrib $VERSION $TAG"
eups list  -s
echo "-----------------------------------------------------------------"
echo ""
echo "Current `umask -p`"

if [ -z  "$PIPE_TASKS_DIR" -o -z "$OBS_SDSS_DIR" ]; then
      echo "FAILURE: ----------------------------------------------------------"
      echo "Failed to setup either PIPE_TASKS or OBS_SDSS; both of  which are required by $DEMO_BASENAME"
      echo "FAILURE: ----------------------------------------------------------"
      exit $BUILDBOT_FAILURE
fi

# Acquire and Load the demo package in buildbot work directory
echo "curl -ko $DEMO_TGZ $DEMO_ROOT/$DEMO_TGZ"
curl -ko $DEMO_TGZ $DEMO_ROOT/$DEMO_TGZ
if [ ! -f $DEMO_TGZ ]; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Failed to acquire demo from: $DEMO_ROOT/$DEMO_TGZ  ."
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi

echo "tar xzf $DEMO_TGZ"
tar xzf $DEMO_TGZ
if [ $? != 0 ]; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Failed to unpack: $DEMO_TGZ"
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi

DEMO_BASENAME=`basename $DEMO_TGZ | sed -e "s/\..*//"`
echo "DEMO_BASENAME: $DEMO_BASENAME"
cd $DEMO_BASENAME
if [ $? != 0 ]; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Failed to find unpacked directory: $DEMO_BASENAME"
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi

pwd
echo "./bin/demo_small.sh"
./bin/demo_small.sh
if [ $? != 0 ]; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Failed during execution of  $DEMO_BASENAME"
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi


# Add column position to each label for ease of reading the output comparison
COLUMNS=`head -1 detected-sources.txt| sed -e "s/^#//" `
j=1
NEWCOLUMNS=`for i in $COLUMNS; do echo -n "$j:$i "; j=$((j+1)); done`
echo "Columns in benchmark datafile:"
echo $NEWCOLUMNS
echo "$HOME/numdiff/bin/numdiff -# 11 detected-sources.txt.expected_small detected-sources.txt"
$BB_ANCESTRAL_HOME/numdiff/bin/numdiff -# 11 detected-sources.txt.expected_small detected-sources.txt
if  [ $? != 0 ]; then
    # preserve diff results
    #LOG_FILE="detected-sources.txt"
    #if [ "$LOG_DEST" ]; then
    #    if [ -f "$LOG_FILE" ]; then
    #        copy_log $LOG_FILE $LOG_FILE $LOG_DEST_HOST $LOG_DEST_DIR $BUILDER_NAME'/build/'$BUILD_NUMBER'/steps/'$STEP_NAME'/logs' $LOG_URL
    #    else
    #            print_error "WARNING: No $LOG_FILE present."
    #    fi
    #else
    #    print_error "WARNING: No archive destination provided for log file."
    #fi

    exit $BUILDBOT_WARNINGS
fi
exit  $BUILDBOT_SUCCESS
