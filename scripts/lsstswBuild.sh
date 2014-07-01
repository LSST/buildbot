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
    if [ "$WORK_DIR" ==  "/usr/local/home/lsstsw" ]; then
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

# The displays provide feedback on the environment existing prior to lsst_build
printenv
echo "eups list lsst_distrib:"
eups list lsst_distrib


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
#  Case 1: uncomment all lines in following block - email sent to lsst-data
#  Case 2: keep commented the lines with '***', and ':::::' -
#          email sent only to Buildbot Nanny.
# Remember to re-comment the entire following block when done testing.
#=================================================================
#echo "Now forcing failure in order to test Buildbot error email delivery"
#echo "*** error building product meas_algorithms."
#echo "*** exit code = 2"
#echo "*** log is in /usr/local/home/lsstsw/build/meas_algorithms/_build.log"
#echo "ctrl_provenance: 8.0.0.0+3 ERROR forced"
#echo ":::::  scons: *** [src/WarpedPsf.os] Error 1"
#echo ":::::  scons: building terminated because of errors."
#echo "*** This is a test of Buildbot error handling system."
#echo "*** I G N O R E this missive."
#echo "This is not en error line"
#echo "::::: This concludes testing of Buildbot error handling for SCONS failures"
#echo "::::: You may resume your normal activities."
#exit $BUILDBOT_FAILURE
#=================================================================

if [ $RET -ne 0 ]; then
    # Archive the failed build artifacts
    print_error "Failed rebuild of DM stack." 
    mkdir -p $LSSTSW/build/$FAILED_LOGS/$BUILD_NUMBER
    for product in $LSSTSW/build/*; do
        # Catch unit testing errors and scons (compile) errors
        if [ -d $product ] &&  \
           [ "`ls $product/tests/.tests/*.failed 2> /dev/null | wc -l`" != "0" ]  || \
           [ -e $product/_build.log ] && \
           [  ! `grep -qs ' \*\*\* \| ::::: \| ERROR ' $product/_build.log` ]; then
            package=`echo $product | sed -e "s/^.*\/build\///"`
            for i in log tags sh; do
            cp -p $product/_build.$i $LSSTSW/build/$FAILED_LOGS/$BUILD_NUMBER/${package}_build.$i
            done
        fi
    done
    echo "The following build artifacts are in directory: $LSSTSW/build/$FAILED_LOGS/$BUILD_NUMBER/"
    ls -l $LSSTSW/build/$FAILED_LOGS/$BUILD_NUMBER
    exit $BUILDBOT_FAILURE 
fi  

# Find current and last EUPS build tag.
eval "$(grep -E '^BUILD=' "$LSSTSW"/build/manifest.txt | sed -e 's/BUILD/TAG/')"
print_error "The DM stack has been installed at $LSSTSW with tag: $TAG."
OLD_TAG=`cat $WORK_DIR/build/BB_Last_Tag`
echo ":LastTag:ThisTag: --> :$OLD_TAG:$TAG:"
if [ "$OLD_TAG" \> "$TAG" ] || [ "$OLD_TAG" == "$TAG" ]; then
    echo "Since no git changes, no need to process further"
    exit $BUILDBOT_SUCCESS
fi

# Build doxygen documentation
cd $LSSTSW/build
$BUILDBOT_SCRIPTS/create_xlinkdocs.sh --type "master" --user "buildbot" --host "lsst-dev.ncsa.illinois.edu" --path "/lsst/home/buildbot/public_html/doxygen"
RET=$?

if [ $RET -eq 2 ]; then
    print_error "Doxygen documentation returned with a warning."
    exit $BUILDBOT_WARNING
elif [ $RET -ne 0 ]; then
    print_error "FAILURE: Doxygen document was not installed."
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
    print_error "The simple integration demo completed with some statistical deviation in the output comparison."
    exit $BUILDBOT_WARNING
elif [ $RET -ne 0 ]; then
    print_error "There was an error running the simple integration demo."
    exit $BUILDBOT_FAILURE
fi
echo "The simple integration demo was successfully run."
