#! /bin/bash
# Build cross linked doxygen documents and load into website

usage() {
    echo "Usage: $0 type destination"
    echo "Build crosslinked doxygen documentation and install on LSST website."
    echo "             type: either \"master\" \"stable\" \"beta\""
    echo "   <host>:/<path>: an scp target for user 'buildbot' "
    echo "                   where host & fullpath directory specify where to receive scp files,"
    echo "                         the remote account is pre-defined to 'buildbot'."
    echo "                   example: \"lsst-build.ncsa.illinois.edu:/var/www/html/doxygen\""
}

#----------------------------------------------------------------------------- 
#  To manually invoke this builbot script, do:
# % <setup eups>
# % cd <buildbot work directory>
# % ~/RHEL6/gitwork/scripts/create_xlinkdocs.sh beta lsst-build5.ncsa.illinois.edu:/lsst/home/buildbot/public_html/doxygen
#----------------------------------------------------------------------------- 
check1() {
    if [ "$1" = "" -o "${1:0:1}" = "-" ]; then
        usage
        exit 1
    fi
}

source $LSST_HOME/loadLSST.sh

source ${0%/*}/build_functions.sh
source ${0%/*}/gitBuildFunctions.sh

DEBUG=debug
DEV_SERVER="lsstdev.ncsa.uiuc.edu"
SCM_SERVER="git.lsstcorp.org"
WEB_HOST="lsst-build5.ncsa.illinois.edu"
WEB_ROOT="/lsst/home/buildbot/public_html/doxygen"

# -------------------
# -- get arguments --
# -------------------
#*************************************************************************
check1 $@
DOXY_TYPE=$1           # 'master' or 'stable'
if [ "$DOXY_TYPE" != "master"  -a "$DOXY_TYPE" != "stable" -a "$DOXY_TYPE" != "beta" ]; then
    usage
    exit 1
fi
SYM_LINK="x_${DOXY_TYPE}DoxyDoc"
echo "DOXY_TYPE: $DOXY_TYPE"
shift

#*************************************************************************
check1 $@
DESTINATION=$1         # buildbot@lsst-build5.ncsa.illinois.edu:/lsst/home/buildbot/public_html/doxygen
REMOTE_USER="buildbot"
REMOTE_HOST="${DESTINATION%%\:*}" # lsst-build5.ncsa.illinois.edu
REMOTE_DIR="${DESTINATION##*\:}"  # /var/www/html/doxygen
shift
#*************************************************************************

DATE="`date +%Y`_`date +%m`_`date +%d`_`date +%H.%M.%S`"

echo "DATE: $DATE"
echo "REMOTE_USER $REMOTE_USER"
echo "DESTINATION: $DESTINATION"
echo "REMOTE_HOST: $REMOTE_HOST"
echo "REMOTE_DIR: $REMOTE_DIR"
echo "DOXY_TYPE: $DOXY_TYPE"


ssh $REMOTE_USER@$REMOTE_HOST pwd
if [ $? != 0 ]; then
    echo "$DESTINATION  does not resolve to a valid URL for account buildbot:  buildbot@<host>:<fullpath>"
    usage
    exit 1
fi

ssh $REMOTE_USER@$REMOTE_HOST  test -e $REMOTE_DIR 
if [ $? != 0 ]; then
    echo "Executed: ssh $REMOTE_USER@$REMOTE_HOST  test -e $REMOTE_DIR"
    echo "Failed to find: $REMOTE_DIR, is the directory valid?"
    usage
    exit 1
fi

WORK_DIR=`pwd`
echo "WORK_DIR: $WORK_DIR"

# SCM checkout devenv/lsstDoxygen ** from master **
prepareSCMDirectory devenv/lsstDoxygen BUILD
if [ $RETVAL != 0 ]; then
    echo "Failed to extract $PACKAGE source directory during setup for BUILD."
    exit 1
fi

# setup all packages required by devenv/lsstDoxygen's eups
cd $SCM_LOCAL_DIR
echo "SCM_LOCAL_DIR: $SCM_LOCAL_DIR"
setup -r .
eups list -s

# Create doxygen output for ALL eups-setup packages
export xlinkdoxy=1

scons 
if [ ! $? ]; then
    echo "Failed to build lsstDoxygen package."
    exit 1
fi

# Now setup for build of Data Release library documentation
echo ""
eups list -v datarel
echo ""

if [ "$DOXY_TYPE" = "master" ] ; then 
    STACK_TYPE_SEARCH="buildslave"
elif [ "$DOXY_TYPE" = "stable" ] ; then
    STACK_TYPE_SEARCH="stable"
else 
    STACK_TYPE_SEARCH="beta"
fi
echo "STACK_TYPE_SEARCH: $STACK_TYPE_SEARCH"
echo ""

DATAREL_VERSION=`eups list datarel | grep "$STACK_TYPE_SEARCH" | awk '{print $1}'`
if [ "X$DATAREL_VERSION" = "X" ]; then
    echo "Failed to find datarel's $DOXY_TYPE version."
    exit 1
fi
echo "DATAREL_VERSION: $DATAREL_VERSION"

setup datarel $DATAREL_VERSION
echo ""
eups list -s
echo ""


$WORK_DIR/$SCM_LOCAL_DIR/bin/makeDocs datarel $DATAREL_VERSION | doxygen -
if [ $? != 0 ] ; then
    echo "Failed to generate DATAREL documentation for $DOXY_TYPE source."
    exit 1
fi

# Documentation built, now move it into place
cd $WORK_DIR/$SCM_LOCAL_DIR/doc

# rename the html directory 
echo "Move the documentation into web position"
DOC_DIR="xlink_${DOXY_TYPE}_$DATE" 
echo "DOC_DIR: $DOC_DIR"
mv html  $DOC_DIR
chmod o+rx $DOC_DIR

# send doxygen output directory (formerly: html) to LSST doc website
ssh $REMOTE_USER@$REMOTE_HOST mkdir -p $REMOTE_DIR/$DOC_DIR
scp -qr $DOC_DIR "$REMOTE_USER@$DESTINATION/"
if [ $? != 0 ]; then
    echo "Failed to copy doxygen documentation: $DOC_DIR to $DESTINATION"
    exit 1
fi
echo "Doxygen documentation from $DOC_DIR copied to $REMOTE_USER@$DESTINATION/$DOC_DIR"
ssh $REMOTE_USER@$REMOTE_HOST chmod +r $REMOTE_DIR/$DOC_DIR


# If old sym link exists, save name of actual directory then remove link
ssh $REMOTE_USER@$REMOTE_HOST  test -e $REMOTE_DIR/$SYM_LINK
if [ $? == 0 ]; then
    echo "Old sym link exists, remove it and prepare to remove the actual dir."
    RET_VALUE=`ssh $REMOTE_USER@$REMOTE_HOST ls -l $REMOTE_DIR/$SYM_LINK | sed -e 's/^.*-> //' -e 's/ //g'`
    OLD_DOXY_DOC_DIR=`basename $RET_VALUE`
    ssh $REMOTE_USER@$REMOTE_HOST rm -f $REMOTE_DIR/$SYM_LINK
fi

# symlink the default xlinkdoxy name to new directory.
echo "Next: ssh $REMOTE_USER@$REMOTE_HOST \"cd $REMOTE_DIR; ln -s  $REMOTE_DIR/$DOC_DIR $SYM_LINK\""
ssh $REMOTE_USER@$REMOTE_HOST "cd $REMOTE_DIR;ln -s $REMOTE_DIR/$DOC_DIR $SYM_LINK"
if [ $? != 0 ]; then
    echo "Failed to symlink: $SYM_LINK, to new doxygen documentation: $DOC_DIR"
    exit 1
fi
echo "Updated symlink: $SYM_LINK, to point to new doxygen documentation: $DOC_DIR."

echo ""
echo "NOTE: crontab should peridocally run a job to remove aged documents."
