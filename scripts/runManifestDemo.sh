#! /bin/bash
# Run the demo code to test DM algorithms

DEBUG=debug

#--------------------------------------------------------------------------
# Standalone invocation for gcc master stack:
#--------------------------------------------------------------------------
# First: setup lsstsw stack
# cd $lsstsw/build
# /lsst/home/buildbot/RHEL6/scripts/runManifestDemo.sh  --builder_name "Dunno" --build_number "1"  --small
# or
# /lsst/home/buildbot/RHEL6/scripts/runManifestDemo.sh  --builder_name "Dunno" --build_number "1"  

#--------------------------------------------------------------------------
usage() {
    echo "Usage: $0 [options]"
    echo "Initiate demonstration run."
    echo
    echo "Options:"
    echo "                  --debug: print out extra debugging info"
    echo "              --tag <id> : eups-tag for eups-setup or defaults to latest master build."
    echo "                 --small : to use small dataset; otherwise a mini-production size will be used."
    echo "    --builder_name <name>: buildbot's build name assigned to run."
    echo "  --build_number <number>: buildbot's build number assigned to run."
    echo "--log_dest <buildbot@host:remotepath>: scp destination_path."
    echo "          --log_url <url>: URL for web-access to the build logs."
    echo "       --step_name <name>: assigned step name in build."
    exit
}

# print to stderr -  Assumes stderr is fd 2. BB prints stderr in red.
print_error() {
    echo $@ > /proc/self/fd/2
}
#--------------------------------------------------------------------------

# Setup LSST buildbot support fnunctions
source ${0%/*}/gitConstants.sh

BUILDER_NAME=""
BUILD_NUMBER=0
LOG_DEST=""
LOG_URL=""
STEP_NAME=""
TAG=""
SIZE=""
SIZE_EXT=""

options=$(getopt -l debug,help,small,builder_name:,build_number:,tag:,log_dest:,log_url:,step_name: -- "$@")

while true
do
    case $1 in
        --debug)        DEBUG=true; shift 1;;
        --help)         usage;;
        --small)        SIZE="small";
                        SIZE_EXT="_small"; 
                        shift 1;;
        --builder_name) BUILDER_NAME=$2; shift 2;;
        --build_number) BUILD_NUMBER=$2; shift 2;;
        --tag)          TAG=$2; shift 2;;
        --log_url)      LOG_URL=$2; shift 2;;
        --log_dest)     LOG_DEST=$2;
                        LOG_DEST_HOST=${LOG_DEST%%\:*}; # buildbot@master
                        LOG_DEST_DIR=${LOG_DEST##*\:};  # /var/www/html/logs
                        shift 2;;
        --step_name)    STEP_NAME=$2; shift 2;;
        --)             break ;;
        *)              [ "$*" != "" ] && usage;
                        break;;
    esac
done


cd ~lsstsw/build
WORK_DIR=`pwd`

# Setup either requested tag or last successfully built lsst_distrib
if [ -n "$TAG" ]; then
    setup -t $TAG lsst_distrib 
else
    setup -j lsst_distrib
    cd $LSST_DISTRIB_DIR/../
    VERSION=`ls | sort -r -n -t+ +1 -2 | head -1`
    setup lsst_distrib $VERSION
fi
#*************************************************************************
echo "----------------------------------------------------------------"
echo "EUPS-tag: $TAG     Version: $VERSION"
echo "BUILDER_NAME: $BUILDER_NAME    BUILD_NUMBER: $BUILD_NUMBER"
echo "Dataset size: $SIZE"
echo "Current `umask -p`"
echo "Setup lsst_distrib "
eups list  -s
echo "-----------------------------------------------------------------"

if [ -z  "$PIPE_TASKS_DIR" -o -z "$OBS_SDSS_DIR" ]; then
      print_error "Failed to setup either PIPE_TASKS or OBS_SDSS; both of  which are required by $DEMO_BASENAME"
      exit $BUILDBOT_FAILURE
fi

# Acquire and Load the demo package in buildbot work directory
echo "curl -ko $DEMO_TGZ $DEMO_ROOT/$DEMO_TGZ"
curl -ko $DEMO_TGZ $DEMO_ROOT/$DEMO_TGZ
if [ ! -f $DEMO_TGZ ]; then
    print_error "Failed to acquire demo from: $DEMO_ROOT/$DEMO_TGZ  ."
    exit $BUILDBOT_FAILURE
fi

echo "tar xzf $DEMO_TGZ"
tar xzf $DEMO_TGZ
if [ $? != 0 ]; then
    print_error "Failed to unpack: $DEMO_TGZ"
    exit $BUILDBOT_FAILURE
fi

DEMO_BASENAME=`basename $DEMO_TGZ | sed -e "s/\..*//"`
echo "DEMO_BASENAME: $DEMO_BASENAME"
cd $DEMO_BASENAME
if [ $? != 0 ]; then
    print_error "Failed to find unpacked directory: $DEMO_BASENAME"
    exit $BUILDBOT_FAILURE
fi

./bin/demo.sh --$SIZE
if [ $? != 0 ]; then
    print_error "Failed during execution of  $DEMO_BASENAME"
    exit $BUILDBOT_FAILURE
fi

# Add column position to each label for ease of reading the output comparison
COLUMNS=`head -1 detected-sources$SIZE_EXT.txt| sed -e "s/^#//" `
j=1
NEWCOLUMNS=`for i in $COLUMNS; do echo -n "$j:$i "; j=$((j+1)); done`
echo "Columns in benchmark datafile:"
echo $NEWCOLUMNS
echo "$BB_ANCESTRAL_HOME/numdiff/bin/numdiff -# 11 detected-sources$SIZE_EXT.txt.expected detected-sources$SIZE_EXT.txt"
$BB_ANCESTRAL_HOME/numdiff/bin/numdiff -# 11 detected-sources$SIZE_EXT.txt.expected detected-sources$SIZE_EXT.txt
if  [ $? != 0 ]; then
    exit $BUILDBOT_WARNINGS
fi
exit  $BUILDBOT_SUCCESS
