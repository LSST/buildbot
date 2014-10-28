#!/bin/bash
#  Install the DM code stack using the lsstsw package procedure: rebuild

# /\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\
#  This script modifies the actual DM stack on the cluster. It therefore 
#  explicitly checks literal strings to ensure that non-standard buildbot 
#  expectations regarding the 'work' directory location are  equivalent.
# /\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\

source ${0%/*}/gitConstants.sh
BUILDBOT_SCRIPTS=$BB_ANCESTRAL_HOME/RHEL6/scripts

# Reuse an existing lsstsw installation
NEW_BUILD="no"     
BUILDER_NAME=""
BUILD_NUMBER="0"
REFS=""
FAILED_LOGS="FailedLogs"

# Buildbot remotely invokes scripts with a stripped down environment.  
umask 002

#---------------------------------------------------------------------------
# print to stderr -  Assumes stderr is fd 2. BB prints stderr in red.
print_error() {
    echo $@ > /proc/self/fd/2
}
#---------------------------------------------------------------------------

WORK_DIR=`pwd`

options=(getopt --long newbuild,builder_name:,build_number:,branch:,email: -- "$@")
while true
do
    case "$1" in
        --builder_name) BUILDER_NAME=$2   ; shift 2 ;;
        --build_number) BUILD_NUMBER="$2" ; shift 2 ;;
        --branch)       BRANCH=$2         ; shift 2 ;;
        --email)        EMAIL=$2          ; shift 2 ;;
        --newbuild)     NEW_BUILD="yes"   ; shift 1 ;;
        --) shift ; break ;;
        *) [ "$*" != "" ] && echo "Parsed options; arguments left are:$*:"
            break;;
    esac
done

if [ "${BRANCH}" == "None" ]; then
    BRANCH="master"
else
    BRANCH="${BRANCH} master"
fi
echo "BRANCH:$BRANCH:"

export REF_LIST=`echo $BRANCH | sed  -e "s/ \+ / /g" -e "s/^/ /" -e "s/ $//" -e "s/ / -r /g"`
echo "REF_LIST: $REF_LIST   pwd: $WORK_DIR    NEW_BUILD: $NEW_BUILD"

if [ "$NEW_BUILD" ==  "no" ]; then
    echo "Check reusable stack has well-formed eups directory"
    if [ "$WORK_DIR" ==  "/lsst/home/lsstsw" ]; then
        export LSSTSW=$WORK_DIR
        export EUPS_PATH=$LSSTSW"/stack"
        . $LSSTSW/bin/setup.sh
        if [ $? -ne 0 ]; then
            print_error "Failed to _setup_ existing stack: $WORK_DIR ."
            exit $BUILDBOT_FAILURE
        fi
    else   # If stack missing, need to recover from backups
        print_error "Failed to find required stack: $WORK_DIR ."
        exit $BUILDBOT_FAILURE
    fi
else
    print_error "This slave does not create new stacks. Contact your buildbot nanny."
    exit $BUILDBOT_FAILURE
fi

# The display provides feedback on the environment existing prior to lsst_build
printenv

if [ ! -w $LSSTSW/build/$FAILED_LOGS ]; then
    print_error "Failed prior to stack rebuild; user unable to write to directory: $LSSTSW/build/$FAILED_LOGS"
    exit $BUILDBOT_FAILURE
fi

# Rebuild the stack if a git pkg changed. 
cd $LSSTSW
if [ ! -f ./bin/rebuild ]; then
     print_error "Failed to find 'rebuild'." 
     exit $BUILDBOT_FAILURE
fi
echo "Rebuild is commencing....stand by; using $REF_LIST"
./bin/rebuild  $REF_LIST 
RET=$?

#=================================================================
# Following is necessary to test failures until a test package is fabricated 
# for this very purpose.
#  Case 1: uncomment all lines in following block - email sent to lsst-dm-dev
#  Case 2: keep commented the lines with '***', and ':::::' -
#          email sent only to Buildbot Nanny.
# Remember to re-comment the entire following block when done testing.
#=================================================================
#echo "Now forcing failure in order to test Buildbot error email delivery"
#echo "*** error building product meas_algorithms."
#echo "*** exit code = 2"
#echo "*** log is in /lsst/home/lsstsw/build/meas_algorithms/_build.log"
#echo "ctrl_provenance: 8.0.0.0+3 ERROR forced"
#echo ":::::  scons: *** [src/WarpedPsf.os] Error 1"
#echo ":::::  scons: building terminated because of errors."
#echo "*** This is a test of Buildbot error handling system."
#echo "*** I G N O R E this missive."
#echo "This is not an error line"
#echo "::::: This concludes testing of Buildbot error handling for SCONS failures"
#echo "::::: You may resume your normal activities."
#exit $BUILDBOT_FAILURE
#=================================================================

# Set current build tag (also used as eups tag per installed package).
eval "$(grep -E '^BUILD=' "$LSSTSW"/build/manifest.txt | sed -e 's/BUILD/TAG/')"

BUILD_STATUS="success" && (( $RET != 0 )) && BUILD_STATUS="failure"
echo "$TAG:$BUILD_NUMBER:$BUILD_STATUS:$BRANCH" >> $LSSTSW/build/eupsTag_buildbotNum

if [ $RET -eq 0 ]; then
    print_error "The DM stack has been installed at $LSSTSW with tag: $TAG."
else
    # Archive the failed build artifacts, if any found.
    mkdir -p $LSSTSW/build/$FAILED_LOGS/$BUILD_NUMBER
    for product in $LSSTSW/build/[[:lower:]]*/ ; do
        PACKAGE=`echo $product | sed -e "s/^.*\/build\///"  -e "s/\///"`
        PKG_FAIL_DIR=$LSSTSW/build/$FAILED_LOGS/$BUILD_NUMBER/${PACKAGE}/
        # Are there failed tests?
        if [ -d $product/tests/.tests/ ] && \
           [ -f $product/tests/.tests/*.failed ] && \
           [ -n "$(ls -A  $product/tests/.tests/*.failed)" ]; then
            mkdir -p  $PKG_FAIL_DIR
            for i in $product/tests/.tests/*.failed; do
                cp -p $i  $PKG_FAIL_DIR/.
            done
            for i in _build.log _build.tags _build.sh; do
                cp -p $product/$i $PKG_FAIL_DIR/.
            done
        # Are there error messages littered in the output?
        elif [ -e $product/_build.log ] && \
            [  ! `grep -qs '\*\*\* \|ERROR ' $product/_build.log` ]; then
            mkdir -p $PKG_FAIL_DIR
            for i in _build.log _build.tags _build.sh; do
                cp -p $product/$i $PKG_FAIL_DIR/.
            done
        fi
    done
    if [ "`ls -A $LSSTSW/build/$FAILED_LOGS/$BUILD_NUMBER`" != "" ]; then
        print_error "Failed during rebuild of DM stack." 
        echo "The following build artifacts are in directory: $LSSTSW/build/$FAILED_LOGS/$BUILD_NUMBER/"
        ls $LSSTSW/build/$FAILED_LOGS/$BUILD_NUMBER/*
la  else
        print_error "Failed during setup prior to stack rebuild."
    fi
    exit $BUILDBOT_FAILURE 
fi  


# Build doxygen documentation
cd $LSSTSW/build
$BUILDBOT_SCRIPTS/create_xlinkdocs.sh --type "master" --user "buildbot" --host "lsst-dev.ncsa.illinois.edu" --path "/lsst/home/buildbot/public_html/doxygen"
RET=$?

if [ $RET -eq 2 ]; then
    print_error "*** Doxygen documentation returned with a warning."
    print_error "*** Review the Buildbot 'stdio' log for build: $BUILD_NUMBER."
    exit $BUILDBOT_WARNING
elif [ $RET -ne 0 ]; then
    print_error "*** FAILURE: Doxygen document was not installed."
    print_error "*** Review the Buildbot 'stdio' log for build: $BUILD_NUMBER."
    exit $BUILDBOT_FAILURE
fi
echo "Doxygen Documentation was installed successfully."

#=================================================================
# Then the BB_LastTag file is updated since full processing completed 
# successfully.
echo -n $TAG >  $WORK_DIR/build/BB_Last_Tag
od -bc $WORK_DIR/build/BB_Last_Tag

#=================================================================
# Finally run a simple test of package integration
cd $LSSTSW/build
$BUILDBOT_SCRIPTS/runManifestDemo.sh --builder_name $BUILDER_NAME --build_number $BUILD_NUMBER --tag $TAG  --small
RET=$?

if [ $RET -eq 2 ]; then
    print_error "*** The simple integration demo completed with some statistical deviation in the output comparison."
    exit $BUILDBOT_WARNING
elif [ $RET -ne 0 ]; then
    print_error "*** There was an error running the simple integration demo."
    print_error "*** Review the Buildbot 'stdio' log for build: $BUILD_NUMBER."
    exit $BUILDBOT_FAILURE
fi
echo "The simple integration demo was successfully run."
