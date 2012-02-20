#!/bin/sh
#export LSST_HOME=/lsst/DC3/stacks/gcc445-RH6/28nov2011
echo "Before loadLSST.sh: LSST_HOME: $LSST_HOME   LSST_DEVEL: $LSST_DEVEL"
echo "Before loadLSST.sh: EUPS_PATH: $EUPS_PATH"
source $LSST_HOME/loadLSST.sh
echo "After loadLSST.sh: LSST_HOME: $LSST_HOME   LSST_DEVEL: $LSST_DEVEL"
echo "After loadLSST.sh: EUPS_PATH: $EUPS_PATH"
cat manifest.list | while read LINE; do
    set $LINE
    #setup $1 $2
    echo "Declare $1 $2"
    #echo executing this: eups declare -vvvvvv -Z $LSST_DEVEL  --force -r $PWD/git/$1/$2 $1 $2
    echo eups declare -Z $LSST_DEVEL --force  -r $PWD/git/$1/$2 $1 $2
    eups declare -Z $LSST_DEVEL --force  -r $PWD/git/$1/$2 $1 $2
    eups list -v $1
done
