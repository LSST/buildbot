#!/bin/sh

# This script eups-declares all packages in the manifest.list
# This is meant to be run from the builds/work directory.

# arguments - all optional
# --debug : includes additional debug logging
# --builder_name : name of this buildbot build e.g. Trunk_vs_Trunk
# --build_number : number assigned to this particular build
# --branch : git-branch from which source was extracted

source ${0%/*}/gitConstants.sh

# -------------------
# -- get arguments --
# -------------------
DEBUG=""
BUILDER_NAME=""
BUILD_NUMBER=""
BRANCH=""

MANIFEST="manifest.list"

options=$(getopt -l debug,branch:,builder_name:,build_number: -- "$@")

while true
do
    case $1 in
        --debug) DEBUG=1; shift 1;;
        --builder_name) BUILDER_NAME=$2; shift 2;;
        --build_number) BUILD_NUMBER=$2; shift 2;;
        --branch) BRANCH=$2; shift 2;;

        *) [ "$*" != "" ] && echo "parsed options; arguments left are:$*:"
             break;;
    esac
done

source $LSST_HOME/loadLSST.sh

if [ ! -e $MANIFEST ] || [ "`cat $MANIFEST | wc -l`" = "0" ]; then
    echo "FATAL: Failed to find file: \"$MANIFEST\" in buildslave work directory."
    exit $BUILDBOT_FAILURE
fi

cat $MANIFEST | while read LINE; do
    set $LINE
    echo "INFO: \"eups declare -Z $LSST_DEVEL --force  -r $PWD/git/$1/$2 $1 $2\""
    eups declare -Z $LSST_DEVEL --force  -r $PWD/git/$1/$2 $1 $2
    eups list -v $1
done
