#!/bin/bash
SCRIPT_DIR=/lsst/home/buildbot/RHEL6/scripts

# -------------------
# -- get arguments --
# -------------------

options=$(getopt -l verbose,branch: -- "$@")

while true
do
    case $1 in
        --verbose) VERBOSE=true; shift;;
        --branch) BRANCH=$2; shift 2;;
        *) echo "parsed options; arguments left are: $*"
             break;;
    esac
done

echo "Branch: $BRANCH"

$SCRIPT_DIR/bootstrap.py $BRANCH >manifest.list
sort manifest.list | awk '{print $1}' >manifest.sorted
echo "==============================================================="
echo "manifest.list"
echo "==============================================================="
cat manifest.sorted

$SCRIPT_DIR/released.py $BRANCH >released.list
cat released.list | awk '{print $1}' | sort >released.sorted
echo "==============================================================="
echo "released.list"
echo "==============================================================="
cat released.sorted

diff manifest.sorted released.sorted >unreleased.txt
echo "==============================================================="
echo "unreleased.txt"
echo "==============================================================="
cat unreleased.txt
exit 0
