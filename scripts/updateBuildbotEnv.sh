#!/bin/sh
umask 002
source $LSST_HOME/loadLSST.sh
echo "sandbox should be at "$1
if [ -d "$1" ]; then
    echo "sandbox directory $1 already exists"
else
    mkdir -p $1
    mksandbox $1
fi
# make sure the parent directory of the sandbox is accessible.  Buildbot
# ignores the umask settings when it is created.
chmod og+rx $1/..

echo "EUPS_USERDATA is set to: $EUPS_USERDATA"
if [ -n "$EUPS_USERDATA" ]; then # if the EUPS_USERDATA var is set
    # create the directory; if it exists already, nothing happens.
    mkdir -p $EUPS_USERDATA
    # if there is no startup.py file, create one with locking turned off.
    if [ ! -f "$EUPS_USERDATA/startup.py" ]; then 
        echo "hooks.config.site.lockDirectoryBase = None" >$EUPS_USERDATA/startup.py
        echo 'hooks.config.Eups.userTags += ["SCM"]' >>$EUPS_USERDATA/startup.py
    else
        echo "$EUPS_USERDATA/startup.py exists, not overwriting"
    fi
fi
