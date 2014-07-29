#! /bin/bash
# Build cross linked doxygen documents and load into buildbot public_html website

source ${0%/*}/gitConstants.sh

DEBUG=debug

usage() {
    echo "Usage: $0 --type <type> --user <remote user on doxy host> --host <remote doxy host> --path  <remote doxy docs path>"
    echo "Build crosslinked doxygen documentation and install on LSST website."
    echo "             type: either <git-branch>,  \"stable\", or \"beta\""
    echo "             user: remote user account with access to directory containing the DM doxygen documentation"
    echo "             host: remote system hosting the publicly accessible DM doxygen documentation"
    echo "             path: actual remote path to the publicly accessible DM doxygen documentation"
    echo "Example: $0 --type master --user buildbot --host lsst-dev.ncsa.illinois.edu --path /usr/local/home/buildbot/public_html/doxygen"
    echo "Example: $0 --type Winter2012 --user buildbot --host lsst-dev.ncsa.illinois.edu --path /usr/local/home/buildbot/public_html/doxygen"
    echo "Example: $0 --type stable --user buildbot --host lsst-dev.ncsa.illinois.edu --path /usr/local/home/buildbot/public_html/doxygen"
}

#----------------------------------------------------------------------------- 
#                         W A R N I N G  
# The following test process will install the documentation of latest master build
# into ~buildbot/public_html/doxygen .
#                         W A R N I N G  
#  To manually invoke this buildbot script,  you need to have your ssh public 
#  key installed in ~buildbot/.ssh/authorized_keys  and then do:
# % <setup eups>
# % cd <your work dir>
# % ~buildbot/RHEL6/scripts/create_xlinkdocs.sh --type master --user buildbot --host lsst-dev.ncsa.illinois.edu --path /lsst/home/buildbot/public_html/doxygen
#----------------------------------------------------------------------------- 
WORK_DIR=`pwd`
echo "WORK_DIR: $WORK_DIR"

options=(getopt --long type:,user:,host:,directory: -- "$@")
while true
do
    case "$1" in
        --type) DOXY_TYPE="$2";   shift 2 ;;
        --user) REMOTE_USER="$2"; shift 2 ;;
        --host) REMOTE_HOST="$2"; shift 2 ;;
        --path) REMOTE_DIR="$2";  shift 2 ;;
        --) shift ; break ;;
        *) [ "$*" != "" ] && echo "Parsed options; arguments left are:$*:"
            break;;
    esac
done


if [ -z "$DOXY_TYPE"  -o  -z "$REMOTE_USER"   -o   -z "$REMOTE_HOST"  -o  -z "$REMOTE_DIR" ]; then
    echo "***  Missing a required input parameter."
    usage
    exit $BUILDBOT_FAILURE
fi

DATE="`date +%Y`_`date +%m`_`date +%d`_`date +%H.%M.%S`"
DESTINATION="$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR"

# Normative doxy_type needs to be one of {normative(<branch>), beta, stable}
#   but doxy_type for master branch will now change to the tag name used 
#   for a master build
NORMATIVE_DOXY_TYPE=`echo $DOXY_TYPE | tr  "/" "_"`
if [ "$DOXY_TYPE" == "master" ]; then
    BUILD_NUM="b"`eups list --raw lsst_distrib | sed -e "s/^.*|//" | sed -e "s/:/\n/g" | sed -e "s/^b//" | grep "^[0-9]" | sort -nr | head -1`
    echo "BUILD_NUM: $BUILD_NUM"
    if [ -z "$BUILD_NUM" ]; then
        echo "*** Failed: to determine most recent master build number."
        exit $BUILDBOT_FAILURE
    else
        DOXY_TYPE=$BUILD_NUM
    fi
fi
SYM_LINK="x_${NORMATIVE_DOXY_TYPE}DoxyDoc"

echo "whoami: "`whoami`
echo "DATE: $DATE"
echo "REMOTE_USER $REMOTE_USER"
echo "REMOTE_HOST: $REMOTE_HOST"
echo "REMOTE_DIR: $REMOTE_DIR"
echo "DESTINATION: $DESTINATION"
echo "DOXY_TYPE: $DOXY_TYPE"
echo "NORMATIVE_DOXY_TYPE: $NORMATIVE_DOXY_TYPE"
echo "SCM_SERVER: $SCM_SERVER"

ssh "$REMOTE_USER@$REMOTE_HOST" pwd
if [ $? != 0 ]; then
    echo "*** $REMOTE_USER@$REMOTE_HOST  is not an accessible URL"
    echo -n "Failed: "; usage
    exit $BUILDBOT_FAILURE
fi
ssh "$REMOTE_USER@$REMOTE_HOST"  test -e $REMOTE_DIR 
if [ $? != 0 ]; then
    echo "*** Failed: \"ssh $REMOTE_USER@$REMOTE_HOST  test -e $REMOTE_DIR\"\n*** Is directory: \"$REMOTE_DIR\" valid?"
    exit $BUILDBOT_FAILURE
fi

# Ensure fresh extraction
cd $WORK_DIR
rm -rf lsstDoxygen
SCM_LOCAL_DIR=lsstDoxygen

# SCM clone devenv/lsstDoxygen ** from master **
git clone git@$SCM_SERVER:LSST/DMS/devenv/lsstDoxygen.git
if [ $? != 0 ]; then
    echo "*** Failed to clone 'devenv/lsstDoxygen.git'."
    exit $BUILDBOT_FAILURE
fi

# setup all packages required by devenv/lsstDoxygen's eups
cd $SCM_LOCAL_DIR
echo "SCM_LOCAL_DIR: $SCM_LOCAL_DIR"
setup -t $DOXY_TYPE -r .
eups list -s

# Create doxygen docs for ALL setup packages; following is magic environment var
export xlinkdoxy=1

scons 
if [  $? != 0 ]; then
    echo "*** Failed to build lsstDoxygen package."
    exit $BUILDBOT_FAILURE
fi

# Now setup for build of Data Release library documentation
DATAREL_VERSION=`eups list -t $DOXY_TYPE datarel | awk '{print $1}'`
if [ -z "$DATAREL_VERSION" ]; then
    echo "*** Failed to find datarel \"$DOXY_TYPE\" version."
    exit $BUILDBOT_FAILURE
fi
echo "DATAREL_VERSION: $DATAREL_VERSION"

setup datarel $DATAREL_VERSION
echo "Packages setup:"
eups list -s
echo ""


$WORK_DIR/$SCM_LOCAL_DIR/bin/makeDocs --nodot datarel $DATAREL_VERSION > MakeDocs.out
if [ $? != 0 ] ; then
    echo "*** Failed to generate complete makeDocs output for \"$DOXY_TYPE\" source."
    exit $BUILDBOT_FAILURE
fi

doxygen MakeDocs.out
if [ $? != 0 ] ; then
    echo "*** Failed to generate doxygen documentation for \"$DOXY_TYPE\" source."
    exit $BUILDBOT_FAILURE
fi

cd $WORK_DIR/$SCM_LOCAL_DIR

# rename the html directory 
echo "Move the documentation into web position"
DOC_DIR="xlink_${NORMATIVE_DOXY_TYPE}_$DATE" 
echo "DOC_DIR: $DOC_DIR"
mv html  $DOC_DIR
chmod o+rx $DOC_DIR

# send doxygen output directory (formerly: html) to LSST doc website
ssh $REMOTE_USER@$REMOTE_HOST mkdir -p $REMOTE_DIR/$DOC_DIR
echo "CMD: scp -qr $WORK_DIR/$SCM_LOCAL_DIR/$DOC_DIR  ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"
scp -qr $WORK_DIR/$SCM_LOCAL_DIR/$DOC_DIR  ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}
if [ $? != 0 ]; then
    echo "*** Failed to copy doxygen documentation: $WORK_DIR/$SCM_LOCAL_DIR/$DOC_DIR to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}"
    exit $BUILDBOT_FAILURE
fi
echo "INFO: Doxygen documentation from \"$DOC_DIR\" copied to \"$DESTINATION/$DOC_DIR\""
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
    echo "*** Failed to symlink: \"$SYM_LINK\", to new doxygen documentation: \"$DOC_DIR\""
    exit $BUILDBOT_FAILURE
fi
echo "INFO: Updated symlink: \"$SYM_LINK\", to point to new doxygen documentation: $DOC_DIR."

