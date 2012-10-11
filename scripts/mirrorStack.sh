#!/bin/bash
#--------------------------------------------------------------------------
usage() {
#80 cols  ................................................................................
    echo "Usage: $0 --config <file> [--id <string>]"
    echo "Mirror a DM code stack using provided configuration file."
    echo " "
    echo "Options:"
    echo "                  --debug: print out extra debugging info"
    echo "          --config <path>: configuration file for mirror-stack build."
    echo "           --id <string> : append string to mirror-stack name."
    echo "                           Default is current date."
    echo "    --builder_name <name>: buildbot build name assigned to run"
    echo "  --build_number <number>: buildbot build number assigned to run"
}
#--------------------------------------------------------------------------

WORK_DIR=`pwd`
SCRIPT_DIR=${0%/*}
echo "work_dir: $WORK_DIR  script_dir: $SCRIPT_DIR"

ID="$(date '+%F-%T')"
echo "ID: $ID"

# -------------------
# -- get arguments --
# -------------------

options=$(getopt -l debug,builder_name:,build_number:,config:,id: -- "$@")

BUILDER_NAME=""
BUILD_NUMBER=0
CONFIG=

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

echo "CONFIG: $CONFIG ID: $ID"

if [ ! -f $CONFIG ]; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Missing configuration file. \n"
    usage
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi

# Copy mirror configuration to 'work' dir accd to buildMirrorStack requirement
echo "cp $CONFIG $WORK_DIR"
cp $CONFIG $WORK_DIR
if [ $? != 0 ]; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Failed to copy mirror config file: $CONFIG, to work dir: $WORK_DIR."
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi


hash $SCRIPT_DIR/buildMirrorStack.sh
if [ $? != 0 ]; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Failed to find script: $SCRIPT_DIR/buildMirrorStack.sh."
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi

# Call it twice, as the first call, if any 'eups distrib install'-s are
# done, may mess up the tags
echo "Calling buildMirrorStack for first time"
$SCRIPT_DIR/buildMirrorStack.sh --config $CONFIG --id "$ID"
PHASE1_RETVAL=$?
if [ "$PHASE1_RETVAL" = "$BUILDBOT_WARNINGS" ] ; then
    echo "WARNING: -----------------------------------------------------------"
    echo "There were some build failures during first phase of mirrored stack build."
    echo "WARNING: -----------------------------------------------------------"
elif  [ "$PHASE1_RETVAL" = "$BUILDBOT_FAILURE" ] ; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "There was a serious failure in the first phase of mirrored stack build."
    echo "Refer to the buildbot stdio log for more information."
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi
echo "Completed first phase of mirrored stack build."

echo "Calling buildMirrorStack for second time"
$SCRIPT_DIR/buildMirrorStack.sh --config $CONFIG --id "$ID" 
PHASE2_RETVAL=$?
echo "Completed mirrored stack build."
if [ "$PHASE2_RETVAL" = "$BUILDBOT_FAILURE" ] ; then
    echo "FAILURE: -----------------------------------------------------------"
    echo "Failed during the re-tagging phase of mirrored stack build."
    echo "Refer to the buildbot stdio log for more information."
    echo "FAILURE: -----------------------------------------------------------"
    exit $BUILDBOT_FAILURE
fi

if [ "$PHASE1_RETVAL" = "$BUILDBOT_WARNINGS" ]  || [ "$PHASE2_RETVAL" = "$BUILDBOT_WARNINGS" ]; then
    echo "WARNING: -----------------------------------------------------------"
    echo "There were some build failures during the mirrored stack build."
    echo "Refer to the buildbot stdio log for more information."
    echo "Guru needs to review and enter permanent failures into configuration's FAILURE list to avoid wasted builds."
    echo "WARNING: -----------------------------------------------------------"
    exit $BUILDBOT_WARNINGS
fi
exit $BUILDBOT_SUCCESS
