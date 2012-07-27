#!/bin/bash

# This script executes a doxygen build.
# This is meant to be run from the builds/work directory.

# arguments
# --package : package we're looking at to see if dependencies are built
# --doxygen_dest : passed to the create_xlinkdocs.sh script
# --doxygen_url : passed to the create_xlinkdocs.sh script
# --debug : includes additional debug logging
# --builder_name : name of this buildbot build e.g. Trunk_vs_Trunk
# --build_number : number assigned to this particular build

source ${0%/*}/gitConstants.sh

DEBUG=""
BUILDER_NAME=""
BUILD_NUMBER=""
DOXYGEN_DEST=""
DOXYGEN_URL=""
PACKAGE=""
BRANCH="master"

##
# get the arguments
##
options=$(getopt -l debug,builder_name:,build_number:,doxygen_dest:,doxygen_url:,package:,branch: -- "$@")

while true
do
        case $1 in
            --debug) DEBUG=1; shift 1;;
            --builder_name) BUILDER_NAME=$2; shift 2;;
            --build_number) BUILD_NUMBER=$2; shift 2;;
            --doxygen_dest) DOXYGEN_DEST=$2; shift 2;;
            --doxygen_url) DOXYGEN_URL=$2; shift 2;;
            --package) PACKAGE=$2; shift 2;;
            --branch) BRANCH=$2; shift 2;;
            *) [ "$*" != "" ] && echo "parsed options; arguments left are:$*:"
                break;;
        esac
done

##
# sanity check to be sure we got all the arguments
##
if [ "$PACKAGE" == "" ] || [ "$DOXYGEN_DEST" == "" ] || [ "$DOXYGEN_URL" == "" ]; then
    echo "FATAL: Usage: $0 --package <package> --doxygen_dest <dir> --doxygen_url <url> [--debug] [--builder_name <string>] [--build_number <#>] [--branch <git-branch>]"
    exit $BUILDBOT_FAILURE
fi

echo ${0%/*}/create_xlinkdocs.sh $BRANCH $DOXYGEN_DEST $DOXYGEN_URL
${0%/*}/create_xlinkdocs.sh $BRANCH $DOXYGEN_DEST $DOXYGEN_URL
STATUS=$?
# Note: create_xlinkdocs.sh returns BUILDBOT_* status
exit $STATUS

