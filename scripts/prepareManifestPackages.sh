#!/bin/sh
BUILDBOT_HOME=$HOME/RHEL6
source $LSST_HOME/loadLSST.sh
ARGS=$*
echo "ARGS ARE: $ARGS"
cat manifest.list | while read LINE; do
    set $LINE
    $BUILDBOT_HOME/scripts/gitPrepareManifestPackage.sh $ARGS  $1
done
