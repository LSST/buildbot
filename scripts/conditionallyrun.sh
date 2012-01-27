#!/bin/bash

# this script checks to see all the dependencies for a given package are
# marked with a BUILD_OK, and if they are, will execute any a doxygen build
# and a production run. This is meant to be run from the builds/work directory.

# arguments
# --package : package we're looking at for to see if dependencies are built
# --script_dir : location of the buildbot scripts. used to invoke other scripts
# --doxygen_dest : passed to the create_xlinkdocs.sh script
# --doxygen_url : passed to the create_xlinkdocs.sh script
DEBUG=""
PACKAGE=""
SCRIPT_DIR=""
DOXYGEN_DEST=""
DOXYGEN_URL=""

##
# get the arguments
##
options=$(getopt -l debug,package:,script_dir:,doxygen_dest:,doxygen_url: -- "$@")

while true
do
        case $1 in
            --debug) DEBUG=1; shift 1;;
            --package) PACKAGE=$2; shift 2;;
            --script_dir) SCRIPT_DIR=$2; shift 2;;
            --doxygen_dest) DOXYGEN_DEST=$2; shift 2;;
            --doxygen_url) DOXYGEN_URL=$2; shift 2;;
            *) echo "parsed options; arguments left are: $*"
                break;;
        esac
done

##
# sanity check to be sure we got all the arguments
##
if [ "$PACKAGE" == "" ] || [ "$SCRIPT_DIR" == "" ] || [ "$DOXYGEN_DEST" == "" ] || [ "$DOXYGEN_URL" == "" ]; then
    echo "usage: $0 --package package --scriptdir di> --doxygen_dest dir --doxygen_url url"
    exit 1
fi

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

# uncomment these when we're ready to run them.
echo $SCRIPT_DIR/create_xlinkdocs.sh trunk $DOXYGEN_BUILD_DST $DOXYGEN_BUILD_URL
echo $SCRIPT_DIR/production_run_script_goes_here

exit 0
~      
