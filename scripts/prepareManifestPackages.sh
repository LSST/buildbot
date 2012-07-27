#!/bin/sh

source ${0%/*}/gitConstants.sh

source $LSST_HOME/loadLSST.sh
MANIFEST="manifest.list"

ARGS=$*
echo "ARGS ARE: $ARGS"

if [ ! -e $MANIFEST ] || [ "`cat $MANIFEST | wc -l`" = "0" ]; then
    echo "FATAL: Failed to find manifest: \"$MANIFEST\" in buildslave work directory."
    exit $BUILDBOT_FAILURE
fi
FINAL_STATUS=$BUILDBOT_SUCCESS
#cat $MANIFEST | while read LINE; do
while read LINE; do
    set $LINE
    ${0%/*}/gitPrepareManifestPackage.sh $ARGS  --package $1
    CUR_STATUS=$?
    echo "Package: $1  git-extraction status: $CUR_STATUS"
    # Note command returns only BUILDBOT_* status responses.
    if [ $CUR_STATUS = $BUILDBOT_FAILURE ]; then
        echo "FATAL: Failed to extract git package: \"$1\" ."
        FINAL_STATUS=$BUILDBOT_FAILURE
        break
    elif [ $CUR_STATUS = $BUILDBOT_WARNINGS ]; then
        FINAL_STATUS=$CUR_STATUS
    fi
done < $MANIFEST
echo "Final exit taken"
exit $FINAL_STATUS
