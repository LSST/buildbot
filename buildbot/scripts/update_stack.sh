#! /bin/bash
# Install a new copy of the LSST stack in /lsst/stacks, alongside the
# old ones.  Name it based on today's date, and make a symbolic link
# to it from "/lsst/stacks/default".

if [ "$1" = "-root" ]; then
    LSST_ROOT=$2
    shift 2
else
    LSST_ROOT="/lsst/stacks"
fi

TODAY=`date +%Y_%m_%d`
LSST_HOME="$LSST_ROOT/$TODAY"
echo "home = $LSST_HOME"

echo 
if [ -d $LSST_HOME ]; then
    echo "Install dir $LSST_HOME already exists; aborting."
    exit 1;
fi