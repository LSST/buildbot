#! /bin/bash

source ${0%/*}/gitConstants.sh

#curl -o newinstall.sh http://dev.lsstcorp.org/tstdms/newinstall.sh
#curl -o newinstall.sh http://lsstdev.ncsa.uiuc.edu/dmspkgs/newinstall.sh
curl -o newinstall.sh http://sw.lsstcorp.org/newinstall.sh
if [ ! -f newinstall.sh ]; then
    echo "Failed to fetch newinstall.sh"
    exit $BUILDBOT_FAILURE
fi

export LSST_HOME=`pwd`
echo "pwd = $LSST_HOME"
bash ./newinstall.sh lsstactive
if [ $? != 0 ]; then
    echo "newinstall.sh failed"
    exit $BUILDBOT_FAILURE
fi
source loadLSST.sh
if [ $? != 0 ]; then
    echo "loadLSST.sh failed"
    exit $BUILDBOT_FAILURE
fi

PYTHON_INSTALLED=`eups list python | wc -l`
if [ $PYTHON_INSTALLED = "1" ]; then
    exit $BUILDBOT_SUCCESS # succeeded - found python installed
elif [ $PYTHON_INSTALLED = "0" ]; then
    echo "No python installed:";
    eups list  python
    exit $BUILDBOT_FAILURE # failed - no python installed
else
    echo "Unexpected: found more than one python installed:";
    eups list  python
    exit $BUILDBOT_FAILURE
fi
