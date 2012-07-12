#!/bin/sh
source ${0%/*}/gitConstants.sh

if [ "x$1" = "x" ]; then
    echo "FATAL: Usage: $0  <local eups directory - new or existing>"
fi
umask 002
unset LSST_DEVEL
source $LSST_HOME/loadLSST.sh
if [ -d "$1" ]; then
    echo "INFO: buildbot eups stack: \"$1\" already exists"
else
    mkdir -p $1
    mksandbox $1
    echo "INFO: buildbot eups stack created at \"$1\""
fi
export LSST_DEVEL=$1

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

# Finally, clear the Blame list which will be used by all other packages to 
# append a blamed developer's email address for later failure notification.
cp /dev/null BlameNotification.list

