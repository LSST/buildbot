#!/bin/sh
#export LSST_HOME=/lsst/DC3/stacks/gcc445-RH6/15nov2011
#export LSST_HOME=/lsst/DC3/stacks/gcc445-RH6/28nov2011
ARGS=$*
BUILDBOT_HOME=$HOME/RHEL6
source $LSST_HOME/loadLSST.sh
which python
echo $PYTHON_PATH
setup `grep datarel manifest.list`
# setup all the packages in the manifest list so that the dependencies are
# acquired from the brand-new source tables not past-due-date packages
while read LINE; do
    set $LINE
    echo "setup -j $1 $2"
    setup -j $1 $2
    eups list -s $1
done < manifest.list
eups list -s -v 

# now find the dependency lists of each setup DM package
python $BUILDBOT_HOME/scripts/dependencies.py $ARGS
