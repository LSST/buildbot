#!/bin/bash

# this script executes a doxygen build.
# This is meant to be initiated by the remote buildmaster within a buildslave's
# 'builds/work' directory. Local environment variables are also passed from the
# buildmaster.


# arguments
# --package : package we're looking at to see if dependencies are built
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
    echo "usage: $0 --package <package> --scriptdir <dir> --doxygen_dest <dir> --doxygen_url <url>"
    exit 1
fi

echo time $SCRIPT_DIR/create_xlinkdocs.sh master $DOXYGEN_DEST $DOXYGEN_URL
time $SCRIPT_DIR/create_xlinkdocs.sh master $DOXYGEN_DEST $DOXYGEN_URL

