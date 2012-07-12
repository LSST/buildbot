#!/bin/bash

# This script creates the manifest files used to drive stack builds:
#   manifest.list/manifest.sorted - all packages in git repos excluding those
#             named in etc/excluded.txt
#   released.list/released.sorted - all packages in the current DMS Release
#   unreleased.tct - packages which are not released yet.
# This is meant to be run from the builds/work directory.

# arguments
# --builder_name : name of this buildbot build e.g. Trunk_vs_Trunk
# --build_number : number assigned to this particular build
# --branch : git-branch from which source will be extracted
# --debug : includes additional debug logging

# -------------------
# -- get arguments --
# -------------------

source ${0%/*}/gitConstants.sh

DEBUG=""
BUILDER_NAME=""
BUILD_NUMBER=""
BRANCH=""
EXCLUDED_REPOS=""

options=$(getopt -l debug,excluded:,branch:,builder_name:,build_number: -- "$@")

while true
do
    case $1 in
        --debug) DEBUG=1; shift 1;;
        --excluded) EXCLUDED_REPOS=$2; shift 2;;
        --builder_name) BUILDER_NAME=$2; shift 2;;
        --build_number) BUILD_NUMBER=$2; shift 2;;
        --branch) BRANCH=$2; shift 2;;

        *) [ "$*" != "" ] && echo "parsed options; arguments left are:$*:"

             break;;
    esac
done

##
# sanity check to be sure we got all the arguments
##
if [ "$BRANCH" == "" ] || [ "$BUILDER_NAME" == "" ]  || [ "$BUILD_NUMBER" == "" ] || [ "$EXCLUDED_REPOS" == "" ]; then
    echo "FATAL: Usage: $0 --excluded <file of excluded git repos> --branch <branch> [--debug] --builder_name <name> --build_number <#>"
    exit $BUILDBOT_FAILURE
fi

echo "Branch: $BRANCH"

${0%/*}/bootstrap.py $BRANCH  $EXCLUDED_REPOS >manifest.list
if [ $? != 0 ]; then
    exit $BUILDBOT_FAILURE
fi
sort manifest.list | awk '{print $1}' >manifest.sorted
echo "==============================================================="
echo "manifest.list"
echo "==============================================================="
cat manifest.list

${0%/*}/released.py $BRANCH >released.list
cat released.list | awk '{print $1}' | sort >released.sorted
echo "==============================================================="
echo "released.list"
echo "==============================================================="
cat released.list

diff manifest.sorted released.sorted >unreleased.txt
echo "==============================================================="
echo "unreleased.txt"
echo "==============================================================="
cat unreleased.txt
exit $BUILDBOT_SUCCESS
