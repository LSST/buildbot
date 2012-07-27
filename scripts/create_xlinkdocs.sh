#! /bin/bash
# Build cross linked doxygen documents and load into website

source ${0%/*}/gitConstants.sh

usage() {
    echo "Usage: $0 type destination"
    echo "Build crosslinked doxygen documentation and install on LSST website."
    echo "             type: either <git-branch>,  \"stable\", or \"beta\""
    echo "   <host>:/<path>: an scp target for user 'buildbot' "
    echo "                   where host & fullpath directory specify where to receive scp files,"
    echo "                         the remote account is pre-defined to 'buildbot'."
    echo "Example: $0 Winter2012 lsst-build.ncsa.illinois.edu:/var/www/html/doxygen"
    echo "Example: $0 stable lsst-build.ncsa.illinois.edu:/var/www/html/doxygen"
}

#----------------------------------------------------------------------------- 
#  To manually invoke this builbot script, do:
# % <setup eups>
# % cd <buildbot work directory>
# % ~/RHEL6/gitwork/scripts/create_xlinkdocs.sh beta lsst-build5.ncsa.illinois.edu:/lsst/home/buildbot/public_html/doxygen
#----------------------------------------------------------------------------- 
check1() {
    if [ "$1" = "" -o "${1:0:1}" = "-" ]; then
        echo -n "FATAL: "
        usage
        exit $BUILDBOT_FAILURE
    fi
}

source $LSST_HOME/loadLSST.sh

source ${0%/*}/gitConstants.sh
source ${0%/*}/build_functions.sh
source ${0%/*}/gitBuildFunctions.sh

DEBUG=debug
WEB_HOST="lsst-build5.ncsa.illinois.edu"

# -------------------
# -- get arguments --
# -------------------
#*************************************************************************
check1 $@
DOXY_TYPE=$1           
NORMATIVE_DOXY_TYPE=`echo $DOXY_TYPE | tr  "/" "_"`
SYM_LINK="x_${NORMATIVE_DOXY_TYPE}DoxyDoc"
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
echo "NORMATIVE_DOXY_TYPE: $NORMATIVE_DOXY_TYPE"


ssh $REMOTE_USER@$REMOTE_HOST pwd
if [ $? != 0 ]; then
    echo "$DESTINATION  does not resolve to a valid URL for account buildbot:  buildbot@<host>:<fullpath>"
    echo -n "FATAL: "
    usage
    exit $BUILDBOT_FAILURE
fi

ssh $REMOTE_USER@$REMOTE_HOST  test -e $REMOTE_DIR 
if [ $? != 0 ]; then
    echo "FATAL: Failed: \"ssh $REMOTE_USER@$REMOTE_HOST  test -e $REMOTE_DIR\"\nIs directory: \"$REMOTE_DIR\" valid?"
    exit $BUILDBOT_FAILURE
fi

WORK_DIR=`pwd`
echo "WORK_DIR: $WORK_DIR"

# Ensure fresh extraction
rm -rf lsstDoxygen
SCM_LOCAL_DIR=lsstDoxygen

# SCM clone devenv/lsstDoxygen ** from master **
clonePackageMasterRepository devenv/lsstDoxygen.git $SCM_LOCAL_DIR
if [ $? != 0 ]; then
    echo "FATAL: Failed to clone 'devenv/lsstDoxygen.git'."
    exit $BUILDBOT_FAILURE
fi

# setup all packages required by devenv/lsstDoxygen's eups
cd $SCM_LOCAL_DIR
echo "SCM_LOCAL_DIR: $SCM_LOCAL_DIR"
setup -r .
eups list -s

# Create doxygen output for ALL eups-setup packages
export xlinkdoxy=1

scons 
if [  $? != 0 ]; then
    echo "FATAL: Failed to build lsstDoxygen package."
    exit $BUILDBOT_FAILURE
fi

# Now setup for build of Data Release library documentation
echo ""
eups list -v datarel
echo ""

if [ "$DOXY_TYPE" = "stable" ] ; then
    STACK_TYPE_SEARCH="stable"
elif  [ "$DOXY_TYPE" = "beta" ] ; then
    STACK_TYPE_SEARCH="beta"
else
    STACK_TYPE_SEARCH="buildslave"
fi
echo "STACK_TYPE_SEARCH: $STACK_TYPE_SEARCH"
echo ""

DATAREL_VERSION=`eups list datarel | grep "$STACK_TYPE_SEARCH" | awk '{print $1}'`
if [ "X$DATAREL_VERSION" = "X" ]; then
    echo "FATAL: Failed to find datarel \"$DOXY_TYPE\" version."
    exit $BUILDBOT_FAILURE
fi
echo "DATAREL_VERSION: $DATAREL_VERSION"

setup datarel $DATAREL_VERSION
echo ""
eups list -s
echo ""


$WORK_DIR/$SCM_LOCAL_DIR/bin/makeDocs datarel $DATAREL_VERSION > MakeDocs.out
if [ $? != 0 ] ; then
    echo "FATAL: Failed to generate complete makeDocs output for \"$DOXY_TYPE\" source."
    exit $BUILDBOT_FAILURE
fi

doxygen MakeDocs.out
if [ $? != 0 ] ; then
    echo "FATAL: Failed to generate doxygen documentation for \"$DOXY_TYPE\" source."
    exit $BUILDBOT_FAILURE
fi

# Documentation built, now move it into place
cd $WORK_DIR/$SCM_LOCAL_DIR/doc

# rename the html directory 
echo "Move the documentation into web position"
DOC_DIR="xlink_${NORMATIVE_DOXY_TYPE}_$DATE" 
echo "DOC_DIR: $DOC_DIR"
mv html  $DOC_DIR
chmod o+rx $DOC_DIR

# send doxygen output directory (formerly: html) to LSST doc website
ssh $REMOTE_USER@$REMOTE_HOST mkdir -p $REMOTE_DIR/$DOC_DIR
scp -qr $DOC_DIR "$REMOTE_USER@$DESTINATION/"
if [ $? != 0 ]; then
    echo "FATAL: Failed to copy doxygen documentation: \"$DOC_DIR\" to \"$DESTINATION\""
    exit $BUILDBOT_FAILURE
fi
echo "INFO: Doxygen documentation from \"$DOC_DIR\" copied to \"$REMOTE_USER@$DESTINATION/$DOC_DIR\""
ssh $REMOTE_USER@$REMOTE_HOST chmod +r $REMOTE_DIR/$DOC_DIR


# If old sym link exists, save name of actual directory then remove link
ssh $REMOTE_USER@$REMOTE_HOST  test -e $REMOTE_DIR/$SYM_LINK
if [ $? == 0 ]; then
    echo "INFO: Old sym link exists, remove it and prepare to remove the actual dir."
    RET_VALUE=`ssh $REMOTE_USER@$REMOTE_HOST ls -l $REMOTE_DIR/$SYM_LINK | sed -e 's/^.*-> //' -e 's/ //g'`
    OLD_DOXY_DOC_DIR=`basename $RET_VALUE`
    ssh $REMOTE_USER@$REMOTE_HOST rm -f $REMOTE_DIR/$SYM_LINK
fi

# symlink the default xlinkdoxy name to new directory.
echo "INFO: ssh $REMOTE_USER@$REMOTE_HOST \"cd $REMOTE_DIR; ln -s  $REMOTE_DIR/$DOC_DIR $SYM_LINK\""
ssh $REMOTE_USER@$REMOTE_HOST "cd $REMOTE_DIR;ln -s $REMOTE_DIR/$DOC_DIR $SYM_LINK"
if [ $? != 0 ]; then
    echo "FATAL: Failed to symlink: \"$SYM_LINK\", to new doxygen documentation: \"$DOC_DIR\""
    exit $BUILDBOT_FAILURE
fi
echo "INFO: Updated symlink: \"$SYM_LINK\", to point to new doxygen documentation: $DOC_DIR."

echo ""
echo "INFO: NOTE: crontab should peridocally run a job to remove aged documents."
