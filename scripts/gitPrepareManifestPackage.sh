#! /bin/bash
# install a requested package from version control, and recursively
# ensure that its minimal dependencies are installed likewise


#--------------------------------------------------------------------------
usage() {
#80 cols  ................................................................................
    echo "Usage: $0 [options] package"
    echo "Install a requested package from version control (master), and recursively"
    echo "ensure that its dependencies are also installed from version control."
    echo
    echo "Options:"
    echo "                --debug: print out extra debugging info"
    echo "  --builder_name <name>: buildslave name"
    echo "  --build_number <number>: buildbot's build number assigned to run"
    echo " where $PWD is location of slave's work directory"
}
#--------------------------------------------------------------------------

DEBUG=debug

source ${0%/*}/gitConstants.sh
source ${0%/*}/build_functions.sh
source ${0%/*}/gitBuildFunctions.sh

PROCESS=${0%/*}

#--------------------------------------------------------------------------

# -------------------
# -- get arguments --
# -------------------

options=$(getopt -l debug,step_name:,log_dest:,log_url:,builder_name:,build_number:,branch:,package: -- "$@")

STEP_NAME="unknown"
BUILDER_NAME=""
BUILD_NUMBER=0
BRANCH="unknown"
PACKAGE="unknown"
while true
do
    case $1 in
        --debug) DEBUG=true; shift;;
        --step_name) STEP_NAME=$2; shift 2;;
        --builder_name)
                BUILDER_NAME=$2; 
                shift 2;;
        --build_number)
                BUILD_NUMBER=$2;
                shift 2;;
        --branch) BRANCH=$2; shift 2;;
        --package) PACKAGE=$2; shift 2;;
        *) [ "$*" != "" ] && echo "parsed options; arguments left are:$*:"
             break;;
    esac
done

step "Determine if $PACKAGE will be tested"

echo "BRANCH = $BRANCH BUILDER_NAME = $BUILDER_NAME  BUILD_NUMBER = $BUILD_NUMBER  STEP_NAME = $STEP_NAME"
if [ "$STEP_NAME" = "unknown" ]; then
    print_error "============================================================="
    print_error "FATAL: Missing argument \"--step_name <name>\" must be specified."
    print_error "============================================================="
    exit $BUILDBOT_FAILURE
fi

if [ "$BRANCH" = "unknown" ]; then
    print_error "============================================================="
    print_error "FATAL: Missing argument \"--branch <git-branch>\" must be specified."
    print_error "============================================================="
    exit $BUILDBOT_FAILURE
fi

if [ ! -d $LSST_DEVEL ] ; then
    print_error "============================================================="
    print_error "FATAL: Environment variable: \"LSST_DEVEL: $LSST_DEVEL\", not a valid directory."
    print_error "============================================================="
    exit $BUILDBOT_FAILURE
fi

if [ "$PACKAGE" = "unknown" ]; then
    print_error "============================================================="
    print_error "FATAL: Missing argument \"--package <name>\" must be specified."
    print_error "============================================================="
    exit $BUILDBOT_FAILURE
fi

WORK_PWD=`pwd`

source $LSST_HOME"/loadLSST.sh"

#*************************************************************************

# Maintain the order or the pseudo packages will need to be included in 
# the package_is_special  check
package_is_external $PACKAGE 
if [ $? = 0 ]; then 
    print_error "============================================================="
    print_error "INFO: External and pseudo packages are not built, \"$PACKAGE\" is one of them."
    print_error "============================================================="
    exit $BUILDBOT_SUCCESS
fi

package_is_special $PACKAGE 
if [ $? = 0 ]; then
    print_error "============================================================="
    print_error "WARNING: Selected packages are not built, \"$PACKAGE\" is one of them."
    print_error "============================================================="
    exit $BUILDBOT_WARNINGS
fi

prepareSCMDirectory $PACKAGE $BRANCH "BOOTSTRAP"
if [ $RETVAL != 0 ]; then
    print_error "============================================================="
    print_error "FATAL: Unable to extract package: \"$PACKAGE\" from git-branch: \"$BRANCH\" during setup for bootstrap dependency."
    print_error "============================================================="
    exit $BUILDBOT_FAILURE
fi
