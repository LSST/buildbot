#!/bin/bash
#  Install the DM code stack 
#          using the lsstsw package procedures: deploy and rebuild

# /\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\
#  In the future, this script will modify the actual DM stack on the cluster. 
#  It therefore explicitly checks literal strings to ensure that non-standard 
#  buildbot expectations regarding the 'work' directory location are 
#  equivalent.
#         
#                N O T E    N O T E    N O T E
#  Since this script is shadowing the real DM stack at the moment, any
#  account reference or directory reference to 'lsstsw2' will ultimately
#  be converted to 'lsstsw' when the cut-over occurs.
#
# /\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\

SCM_SERVER="git@git.lsstcorp.org"

BUILDBOT_SUCCESS=0
BUILDBOT_FAILURE=1
BUILDBOT_WARNINGS=2

# Local setup
# Reuse a existing lsstsw installation
NEW_BUILD="no"     
BUILDER_NAME=""
BUILD_NUMBER="0"
REFS=""

# Setup buildbot environment. Buildbot remotely invokes scripts with a 
# stripped down environment.  
umask 002

#---------------------------------------------------------------------------
# print to stderr -  Assumes stderr is fd 2. BB prints stderr in red.
print_error() {
    echo $@ > /proc/self/fd/2
}
#---------------------------------------------------------------------------

WORK_DIR=`pwd`

options=(getopt --long newbuild,builder_name:,build_number:,branch: -- "$@")
while true
do
    case "$1" in
        --builder_name) BUILDER_NAME=$2   ; shift 2 ;;
        --build_number) BUILD_NUMBER="$2" ; shift 2 ;;
        --branch)       BRANCH=$2         ; shift 2 ;;
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
    if [ "$WORK_DIR" ==  "/usr/local/home/lsstsw2" ]; then
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
eups list

cd $LSSTSW

if [ ! -f ./bin/rebuild ]; then
     print_error "Failed to find 'rebuild'." 
     exit $BUILDBOT_FAILURE}
fi

#
echo "Rebuild is commencing....stand by; using $REF_LIST"
./bin/rebuild  $REF_LIST
RET=$?

#=================================================================
# Following is necessary to test failures until a test package is fabricated 
# for this very purpose.
#  Case 1: uncomment all lines in following block - email sent to lsst-data
#  Case 2: keep the lines with 'ERROR', '***', and ':::::' commented -
#          email sent only to Buildbot Nanny.
# Remember to comment the whole following block when done testing.
#=================================================================
#echo "Now forcing failure in order to test Buildbot error email delivery"
#echo "ctrl_provenance: 8.0.0.0+3 ERROR forced"
#echo "*** This is a test of Buildbot error handling system."
#echo "*** I G N O R E this missive."
#echo "This is not en error line"
#echo "::::: This concludes testing of Buildbot error handling for SCONS failures"
#echo "::::: You may resume your normal activities."
#exit $BUILDBOT_FAILURE
#=================================================================


if [ $RET -eq 0 ]; then
    print_error "Congratulations, the DM stack has been installed at $LSSTSW."
    exit $BUILDBOT_SUCCESS
fi  
print_error "Failed rebuild of DM stack." 
exit $BUILDBOT_FAILURE 
