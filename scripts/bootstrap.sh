#!/bin/bash
SCRIPT_DIR=/lsst/home/buildbot/RHEL6/scripts

$SCRIPT_DIR/bootstrap.py >manifest.list
sort manifest.list | awk '{print $1}' >manifest.sorted
echo "==============================================================="
echo "manifest.list"
echo "==============================================================="
cat manifest.sorted

$SCRIPT_DIR/released.py >released.list
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
