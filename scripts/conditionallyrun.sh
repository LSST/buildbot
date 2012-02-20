#!/bin/bash

# this script checks to see all the dependencies for a given package are
# marked with a BUILD_OK, and if they are, will create a manifest file for
# the last successfully run build.
# This is meant to be run from the builds/work directory.

# arguments
# --package : package we're looking at for to see if dependencies are built
# --script_dir : location of the buildbot scripts. used to invoke other scripts
# --builder_name : name of this buildbot build e.g. TvT
# --build_number : number assigned to this particular build
#
DEBUG=""
PACKAGE=""
SCRIPT_DIR=""
BUILDER_NAME=""
BUILD_NUMBER=""

LAST_SUCCESSFUL_MANIFEST="lastSuccessfulBuildManifest.list"

##
# get the arguments
##
options=$(getopt -l debug,package:,script_dir:,builder_name:,build_number: -- "$@")

while true
do
        case $1 in
            --debug) DEBUG=1; shift 1;;
            --package) PACKAGE=$2; shift 2;;
            --script_dir) SCRIPT_DIR=$2; shift 2;;
            --builder_name) BUILDER_NAME=$2; shift 2;;
            --build_number) BUILD_NUMBER=$2; shift 2;;

            *) echo "parsed options; arguments left are: $*"
                break;;
        esac
done

##
# sanity check to be sure we got all the arguments
##
if [ "$PACKAGE" == "" ] || [ "$SCRIPT_DIR" == "" ] || [ "$BUILDER_NAME" == "" ]  || [ "$BUILD_NUMBER" == "" ]; then
    echo "usage: $0 --package <package> --scriptdir <dir> --builder_name <name> --build_number <#>"
    exit 1
fi

#
## Initialize eups for later capture of accurate versions used/built this build
#
source $LSST_HOME/loadLSST.sh

##
# grab the version of $PACKAGE from the manifest.list file
##
VERSION=`grep -w $PACKAGE manifest.list | awk '{ print $2 }'`

if [ "$DEBUG" != "" ]; then
    echo ls git/$PACKAGE/$VERSION
fi

##
# specify the internal dependencies file we're going to use to look up
# the packages that should all be built properly.
##
INTERNAL=git/$PACKAGE/$VERSION/internal.deps
if [ ! -f "$INTERNAL" ]; then
    echo "error: Can't find $INTERNAL. Exiting."
    exit 1
fi

EXTERNAL=git/$PACKAGE/$VERSION/external.deps
if [ ! -f "$EXTERNAL" ]; then
    echo "error: Can't find $EXTERNAL. Exiting."
    exit 1
fi

DO_NOT_CONTINUE=0
while read LINE; do
    set $LINE
    if [ "$DEBUG" != "" ]; then
        echo setup $2 $3
        echo "Declare $2 $3"
        echo "checking git/$2/$3/BUILD_OK"
    fi
    if [ ! -f "git/$2/$3/BUILD_OK" ]; then
        echo "error: Package $2 $3 not built."
        DO_NOT_CONTINUE=1
    fi
done < $INTERNAL

if [ "$DO_NOT_CONTINUE" != "0" ]; then
    echo "Can not continue.  Exiting."
    exit 1
fi
echo "PWD: `pwd`"
eups list
echo "/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/"
eups list | grep TvT
echo "/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/"

rm -f tmp$LAST_SUCCESSFUL_MANIFEST
eups list | grep TvT > tmp$LAST_SUCCESSFUL_MANIFEST
echo "/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/"
echo "Contents of tmp$LAST_SUCCESSFUL_MANIFEST"
cat tmp$LAST_SUCCESSFUL_MANIFEST
echo "/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/"
if [ "`cat tmp$LAST_SUCCESSFUL_MANIFEST | wc -l`" = 0 ]; then
    echo "Failed to build specific manifest list for archival.  Exiting."
    exit 1
fi

cp tmp$LAST_SUCCESSFUL_MANIFEST $LAST_SUCCESSFUL_MANIFEST
cat $EXTERNAL >> $LAST_SUCCESSFUL_MANIFEST

echo "$LAST_SUCCESSFUL_MANIFEST for package: $PACKAGE"
cat $LAST_SUCCESSFUL_MANIFEST

exit 0
~      
