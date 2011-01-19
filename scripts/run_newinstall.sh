#! /bin/bash

#curl -o newinstall.sh http://dev.lsstcorp.org/tstdms/newinstall.sh
curl -o newinstall.sh http://lsstdev.ncsa.uiuc.edu/dmspkgs/newinstall.sh
if [ ! -f newinstall.sh ]; then
    echo "Failed to fetch newinstall.sh"
    exit 1
fi

export LSST_HOME=`pwd`
echo "pwd = $LSST_HOME"
bash ./newinstall.sh
if [ $? != 0 ]; then
    echo "newinstall.sh failed"
    exit 1
fi
source loadLSST.sh
if [ $? != 0 ]; then
    echo "loadLSST.sh failed"
    exit 1
fi

PYTHON_INSTALLED=`eups list -s python | wc -l`
if [ $PYTHON_INSTALLED = "1" ]; then
    exit 0 # succeeded - found python installed
elif [ $PYTHON_INSTALLED = "0" ]; then
    echo "No python installed:";
    eups list -s python
    exit 1 # failed - no python installed
else
    echo "Unexpected: found more than one python installed:";
    eups list -s python
    exit 1
fi
