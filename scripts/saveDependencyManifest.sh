#!/bin/bash

# this script creates a dependency-ordered manifest file of
# packages eups-tagged with "SCM" which flag a successful package build.
# This is meant to be run from the builds/work directory.

# arguments
# --package : package we're looking at for to see if dependencies are built
# --builder_name : name of this buildbot build e.g. Trunk_vs_Trunk
# --build_number : number assigned to this particular build
#
source ${0%/*}/gitConstants.sh

DEBUG=""
PACKAGE=""
BUILDER_NAME=""
BUILD_NUMBER=""

LAST_SUCCESSFUL_MANIFEST="lastSuccessfulBuildManifest.list"
MANIFEST="manifest.list"

##
# get the arguments
##
options=$(getopt -l debug,package:,builder_name:,build_number: -- "$@")

while true
do
        case $1 in
            --debug) DEBUG=1; shift 1;;
            --builder_name) BUILDER_NAME=$2; shift 2;;
            --build_number) BUILD_NUMBER=$2; shift 2;;
            --package) PACKAGE=$2; shift 2;;

            *) [ "$*" != "" ] && echo "parsed options; arguments left are:$*:"
                break;;
        esac
done

##
# sanity check to be sure we got all the arguments
##
if [ "$PACKAGE" == "" ] ; then
    echo "FAILED: Usage: $0 --package <package> [debug] [--builder_name <name>] [--build_number <#>]"
    exit $BUILDBOT_FAILURE
fi

#
## Initialize eups for later capture of accurate versions used/built this build
#
source $LSST_HOME/loadLSST.sh

##
# grab the version of $PACKAGE from the MANIFEST file
##
VERSION=`grep -w $PACKAGE $MANIFEST | awk '{ print $2 }'`

if [ "$DEBUG" != "" ]; then
    echo ls git/$PACKAGE/$VERSION
fi

##
# specify the internal dependencies file we're going to use to look up
# the packages that should all be built properly.
##
INTERNAL=git/$PACKAGE/$VERSION/internal.deps
if [ ! -f "$INTERNAL" ]; then
    echo "FATAL: Can't find \"$INTERNAL\". Exiting."
    exit $BUILDBOT_FAILURE
fi

EXTERNAL=git/$PACKAGE/$VERSION/external.deps
if [ ! -f "$EXTERNAL" ]; then
    echo "FATAL:: Can't find \"$EXTERNAL\". Exiting."
    exit $BUILDBOT_FAILURE
fi

DO_NOT_CONTINUE=0
while read LINE; do
    set $LINE
    if [ "$DEBUG" != "" ]; then
        echo "checking git/$1/$2/BUILD_OK"
    fi
    if [ ! -f "git/$1/$2/BUILD_OK" ]; then
        echo "FATAL: Package \"$1 $2\" not built."
        DO_NOT_CONTINUE=1
    fi
done < $INTERNAL

if [ "$DO_NOT_CONTINUE" != "0" ]; then
    exit $BUILDBOT_FAILURE
fi

echo "/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/"
eups list
echo "/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/"
eups list -t SCM
echo "/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/"

rm -f tmp$LAST_SUCCESSFUL_MANIFEST
eups list -t SCM > tmp$LAST_SUCCESSFUL_MANIFEST
if [ "`cat tmp$LAST_SUCCESSFUL_MANIFEST | wc -l`" = 0 ]; then
    echo "FATAL: Failed to build specific \"$MANIFEST\" for archival."
    exit $BUILDBOT_FAILURE
fi

cp tmp$LAST_SUCCESSFUL_MANIFEST $LAST_SUCCESSFUL_MANIFEST
cat $EXTERNAL >> $LAST_SUCCESSFUL_MANIFEST

echo "INFO: \"$LAST_SUCCESSFUL_MANIFEST\" for package: \"$PACKAGE\""
cat $LAST_SUCCESSFUL_MANIFEST

exit $BUILDBOT_SUCCESS

