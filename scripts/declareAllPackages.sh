#!/bin/sh
#export LSST_HOME=/lsst/DC3/stacks/gcc445-RH6/15nov2011
source $LSST_HOME/loadLSST.sh
cat manifest.list | while read LINE; do
    set $LINE
    #setup $1 $2
    echo "Declare $1 $2"
    eups declare --force -r git/$1/$2 $1 $2
done
