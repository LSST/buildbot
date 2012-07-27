#! /bin/bash

# This script builds a stack using the tagged versions of packages named in the
# tag's manifest list.  The resultant stack is then checked to ensure that only
# a single version of a package has been used during the stack's build process.
#
# If the tag's manifest file does not contain the 'lsstactive' pseudo package,
# the build is aborted. The 'lsstactive' package lists the full set of
# packages (and 3rd party tools) required to build an endtoend testable stack.

source ${0%/*}/gitConstants.sh

options=$(getopt -l debug,tag:,manifest: -- "$@")

TAG=
MANIFEST=
while true
do
    case $1 in
        --debug)        DEBUG=true; shift;;
        --tag)          TAG=$2;  shift 2;;
        --manifest)     MANIFEST=$2; shift 2;;
        *) [ "$*" != "" ] && echo "parsed options; arguments left are:$*:"
             break;;
    esac
done

WORK_DIR=`pwd`

if [ "x$MANIFEST" = "x" ] ; then
    MANIFEST="$WORK_DIR/lastSuccessfulBuildManifest.list"
    echo "No input manifest file name, using default: $MANIFEST"
fi
if [ "x$TAG" = "x"  ]; then
    echo "FAILURE: Failed to provide tag to use for tagInstall."
    exit $BUILDBOT_FAILURE
fi

export LSST_HOME=$WORK_DIR
echo "LSST_HOME = $LSST_HOME"

gotLsstactive=`curl -s $MANIFEST_LISTS_ROOT_URL/$TAG\.list | grep "^lsstactive"`
if [ ! "$gotLsstactive" ]; then
    echo "FAILURE: Incomplete-stack tag manifest list; missing lsstactive".
    exit $BUILDBOT_FAILURE
fi

if [ "$TAG" = "stable" ] ; then
    #---------------------------------------------------------------------
    # Following is External Users' method of installing stack
    #---------------------------------------------------------------------
    curl -o newinstall.sh http://dev.lsstcorp.org/pkgs/std/w12/newinstall.sh
    if [ ! -f newinstall.sh ]; then
        echo "Failed to fetch newinstall.sh"
        exit $BUILDBOT_FAILURE
    fi

    bash ./newinstall.sh lsstactive
    if [ $? != 0 ]; then
        echo "newinstall.sh failed"
        exit $BUILDBOT_FAILURE
    fi
else
    # Install basic packages enabling eups and scons use, then build lsstactive
    bash ${0%/*}/tagInstall.sh  -t $TAG lsstactive
    STATUS=$?
    if [ $STATUS != 0 ]; then
        echo "FAILURE: Completed installation of $TAG 'lsstactive' with status: $STATUS"
        # Note: tagInstall.sh is BUILDBOT_{SUCCESS FAILURE WARNINGS) enabled
        exit $STATUS
    fi
fi

source loadLSST.sh
if [ $? != 0 ]; then
    echo "FAILURE: loadLSST.sh failed"
    exit $BUILDBOT_FAILURE
fi

echo "================================================================="
echo "Final eups $TAG stack list"
echo "================================================================="
eups list 

# Now determine if there are any packages with multiple versions represented
#   Note scons* may be loaded with an earlier version during initial eups
#        bootstrap, later when creating real stack, a new scons* is loaded.
eups list | grep -v scons | sort +0 -0 > unsortedEups.list
eups list | grep -v scons | sort +0 -0 -u > sortedUniqEups.list
if [ "x`diff unsortedEups.list sortedUniqEups.list`" != "x" ]; then
   echo "Found instance(s) of a package with multiple versions declared"
   package=`diff unsortedEups.list sortedUniqEups.list | grep -v "^[0-9]" | awk "{print $2}"`
   echo "================================================================="
   echo "FAILURE: Inconsistent stack using multi-version package(s): "
   echo "$package"
   echo "================================================================="
   exit $BUILDBOT_FAILURE
fi

# -- Save stack contents into file named by MANIFEST input param
eups list  > $MANIFEST
if [ $? != 0 ]; then
    echo "Failed to save a manifest list to $WORK_DIR/$MANIFEST"
    exit $BUILDBOT_FAILURE
fi

# Test carried over from the dark ages, must have had this failure in the past
PYTHON_INSTALLED=`eups list python | wc -l`
if [ $PYTHON_INSTALLED = "1" ]; then
    exit $BUILDBOT_SUCCESS # succeeded - found single python installed
elif [ $PYTHON_INSTALLED = "0" ]; then
    echo "FAILURE: No python installed:";
    eups list  python
    exit $BUILDBOT_FAILURE # failed - no python installed
fi
echo "FAILURE: Unexpected: found more than one python installed:";
eups list  python
exit $BUILDBOT_FAILURE

