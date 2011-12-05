#! /bin/bash
# Build cross linked doxygen documents and load into website

usage() {
    echo "Usage: $0 destination url_prefix "
    echo "Build crosslinked doxygen documentation and install on LSST website."
    echo "          type: either \"trunk\" or \"current\""
    echo "   destination: an scp target -- username, host & directory to scp files to,"
    echo "                such as \"buildbot@willy.ncsa.illinois.edu:/var/www/html/doxygen\""
    echo "    url_prefix: the beginning of a URL that points to the destination,"
    echo "                such as \"http://dev.lsstcorp.org/doxygen\""
}

check1() {
    if [ "$1" = "" -o "${1:0:1}" = "-" ]; then
        usage
        exit 1
    fi
}

source $LSST_HOME/loadLSST.sh
#source /usr/local/home/buildbot/buildslave/Release/work/loadLSST.sh

source ${0%/*}/build_functions.sh

DEBUG=debug
DEV_SERVER="lsstdev.ncsa.uiuc.edu"
SVN_SERVER="svn.lsstcorp.org"
#WEB_HOST="willy.ncsa.illinois.edu"
#WEB_ROOT="/var/www/html/doxygen"
WEB_HOST="lsst-build.ncsa.illinois.edu"
WEB_ROOT="/usr/local/home/buildbot/www/"

# -------------------
# -- get arguments --
# -------------------
#*************************************************************************
check1 $@
DOXY_TYPE=$1           # 'trunk' or 'current'
if [ "$DOXY_TYPE" != "trunk"  -a "$DOXY_TYPE" != "current" ]; then
    usage
    exit 1
fi
SYM_LINK="x_${DOXY_TYPE}DoxyDoc"
echo "DOXY_TYPE: $DOXY_TYPE"
shift

#*************************************************************************
check1 $@
DESTINATION=$1         # buildbot@willy.ncsa.illinois.edu:/var/www/html/doxygen
REMOTE_HOST=${DESTINATION%%\:*} # buildbot@willy.ncsa.illinois.edu
REMOTE_DIR=${DESTINATION##*\:}  # /var/www/html/doxygen
shift
#*************************************************************************
check1 $@
URL_PREFIX=$1
shift
#*************************************************************************

DATE="`date +%Y`_`date +%m`_`date +%d`_`date +%H.%M.%S`"

echo "DATE: $DATE"
echo "DESTINATION: $DESTINATION"
echo "REMOTE_HOST: $REMOTE_HOST"
echo "REMOTE_DIR: $REMOTE_DIR"
echo "DOXY_TYPE: $DOXY_TYPE"

# svn checkout devenv_doc ** from trunk **
prepareSvnDir devenv_doc
if [ $RETVAL != 0 ]; then
    echo "devenv_doc svn checkout or update failed; contact the LSST buildbot developer"
    exit 1
fi

# devenv_doc should have its eups table setup all packages in Latest Release
cd $SVN_LOCAL_DIR
setup -r .
eups list  -s

# Create doxygen output for ALL eups-setup packages
export xlinkdoxy=1
pretty_execute scons doxygen
if [ $RETVAL != 0 ]; then
    echo "Build of cross-linked doxygen documentation failed."
    exit 1
fi
cd doxygen

# rename the htmlDir 
DOC_DIR="xlink_${DOXY_TYPE}_$DATE" 
echo "DOC_DIR: $DOC_DIR"
mv htmlDir  $DOC_DIR
chmod o+rx $DOC_DIR

# send doxygen output directory (formerly: htmlDir) to LSST doc website
ssh $REMOTE_HOST "mkdir -p $REMOTE_DIR/$DOC_DIR"
scp -qr $DOC_DIR "$DESTINATION/"
if [ $? != 0 ]; then
    echo "Failed to copy doxygen documentation: $DOC_DIR to $DESTINATION"
    exit 1
fi
echo "Doxygen documentation from $DOC_DIR copied to $DESTINATION/$DOC_DIR"
ssh $REMOTE_HOST "chmod +r $REMOTE_DIR/$DOC_DIR"

# Save the actual name of the old doxygen directory
OLD_DOXY_DOC_DIR=`ssh $REMOTE_HOST "if [ -s $REMOTE_DIR/$SYM_LINK ]; then ls -l $REMOTE_DIR/$SYM_LINK | sed -e 's/^.*-> //' -e 's/ //g'; fi"`
echo "Old DoxyDir: $OLD_DOXY_DOC_DIR"

# symlink the default xlinkdoxy name to new directory.
ssh $REMOTE_HOST "rm -f $REMOTE_DIR/$SYM_LINK; ln -s $REMOTE_DIR/$DOC_DIR $REMOTE_DIR/$SYM_LINK"
if [ $? != 0 ]; then
    echo "Failed to symlink: $SYM_LINK, to new doxygen documentation: $DOC_DIR"
    exit 1
fi
echo "Updated symlink: $SYM_LINK, to point to new doxygen documentation: $DOC_DIR."

# OK, time to remove the old document directory
#ssh $REMOTE_HOST "if [ -d $OLD_DOXY_DOC_DIR ] ; then rm -r $OLD_DOXY_DOC_DIR; fi"
ssh $REMOTE_HOST "rm -fr $OLD_DOXY_DOC_DIR"
if [ $? != 0 ]; then
    echo "Failed to remove the previous doxy directory: $OLD_DOXY_DOC_DIR"
    exit 1
fi

