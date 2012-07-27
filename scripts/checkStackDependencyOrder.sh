#!/bin/bash

# This script compares the static buildmaster's RHEL6/etc/LsstStackManifest.list
# against a nightly generated ordering: builds/<builder>/AllBuildOrderManifest,
# generated during the  "extract dependencies" step.
# If the comparison is not identical, email is sent to the Cluster stack 
# guru for updating.

source ${0%/*}/gitConstants.sh
source ${0%/*}/build_functions.sh

MASTER_MANIFEST=""
NIGHTLY_MANIFEST=""

options=$(getopt -l master:,nightly: -- "$@")

while true
do
    case $1 in
        --master) MASTER_MANIFEST=$2; shift 2;;
        --nightly) NIGHTLY_MANIFEST=$2; shift 2;;
        *) [ "$*" != "" ] && echo "parsed options; arguments left are:$*:"
             break;;
    esac
done

if [ "$NIGHTLY_MANIFEST" == "" ] || [ "$MASTER_MANIFEST" == "" ]; then
    print_error "=============================================================" 
    print_error "FAILURE: Usage: $0 --master <LsstStackManifest path> --nightly <AllBuildOrderManifest path>"
    print_error "=============================================================" 
    exit $BUILDBOT_FAILURE
fi

if [ ! -e "$NIGHTLY_MANIFEST" ]; then
    print_error "=============================================================" 
    print_error "FAILURE: Nightly  manifest file: $NIGHTLY_MANIFEST does not exist."
    print_error "FAILURE: Can not check dependency ordering is up-to-date."
    print_error "=============================================================" 
    exit $BUILDBOT_FAILURE
fi

if [ ! -e "$MASTER_MANIFEST" ]; then
    print_error "=============================================================" 
    print_error "FAILURE: Master  manifest file: $MASTER_MANIFEST does not exist."
    print_error "FAILURE: Can not check dependency ordering is up-to-date."
    print_error "=============================================================" 
    exit $BUILDBOT_FAILURE
fi

# Now remove the datasets which don't have dependencies

if [ "`diff -b -B $MASTER_MANIFEST $NIGHTLY_MANIFEST | wc -l`" != "0" ]; then
#   email sent by buildmaster mailNotifier on FAILURE or WARNINGS return
    print_error "diff -b -B $MASTER_MANIFEST $NIGHTLY_MANIFEST"
    print_error "`diff -b -B $MASTER_MANIFEST $NIGHTLY_MANIFEST`"
    print_error "FAILURE: =============================================================" 
    print_error "FAILURE: Out-of-date Master Stack manifest: $MASTER_MANIFEST."
    print_error "FAILURE: Edit & Copy from: $NIGHTLY_MANIFEST." 
    print_error "FAILURE: =============================================================" 
    exit $BUILDBOT_WARNINGS
fi
exit $BUILDBOT_SUCCESS
