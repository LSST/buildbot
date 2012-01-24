#!/bin/sh
#export LSST_HOME=/lsst/DC3/stacks/gcc445-RH6/15nov2011
#export LSST_HOME=/lsst/DC3/stacks/gcc445-RH6/28nov2011
BUILDBOT_HOME=$HOME/RHEL6
source $LSST_HOME/loadLSST.sh
which python
echo $PYTHON_PATH
eups list
python $BUILDBOT_HOME/scripts/dependencies.py $*
