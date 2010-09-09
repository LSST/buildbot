#! /bin/bash
# install a requested package from version control, and recursively
# ensure that its minimal dependencies are installed likewise

usage() {
#80 cols  ................................................................................
    echo "Usage: $0 [options] package"
    echo "Install a requested package from version control (trunk), and recursively"
    echo "ensure that its dependencies are also installed from version control."
    echo
    echo "Options (must be in this order):"
    echo "          -verbose: print out extra debugging info"
    echo "            -force: if the package is already installed, re-install it"
    echo "         -indent N: spaces to indent output as a hint to recursion depth"
    echo " -dont_log_success: if specified, only save logs if install fails"
    echo "  -log_dest <dest>: scp destination for config.log,"
    echo "                    for example \"buildbot@master:/var/www/html/logs\""
    echo "    -log_url <url>: URL prefix for the log destination,"
    echo "                    for example \"http://master/logs/\""
}
source /lsst/stacks/default/loadLSST.sh
source ${0%/*}/build_functions.sh

DEBUG=debug
DEV_SERVER="lsstdev.ncsa.uiuc.edu"
SVN_SERVER="svn.lsstcorp.org"
WEB_ROOT="/var/www/html/doxygen"


# -------------------
# -- get arguments --
# -------------------
if [ "$1" = "-verbose" -o "$1" = "-debug" ]; then
    VERBOSE=true
    shift
fi
if [ "$1" = "-force" ]; then
    FORCE=true
    shift
fi
if [ ! "$1" ]; then
    usage
    exit 1
fi

if [ "$1" = "-indent" ]; then
    INDENT=$2
    shift 2
fi


if [ "$1" = "-dont_log_success" ]; then
    shift
else
    LOG_SUCCESS="true"
fi

if [ "$1" = "-log_dest" ]; then
    LOG_ARGS="$LOG_ARGS $1 $2"
    LOG_DEST=$2
    LOG_DEST_HOST=${LOG_DEST%%\:*} # buildbot@master
    LOG_DEST_DIR=${LOG_DEST##*\:}  # /var/www/html/logs
    shift 2
fi

if [ "$1" = "-log_url" ]; then
    LOG_ARGS="$LOG_ARGS $1 $2"
    LOG_URL=$2
    shift 2
fi
PACKAGE=$1

WORK_PWD=`pwd`

#*************************************************************************

#*************************************************************************
step "Determine if $PACKAGE will be tested"

package_is_external $PACKAGE
if [ $? = 0 ]; then 
    print "External packages are not tested via trunk-vs-trunk"
    exit 0
fi
if [ ${PACKAGE:0:5} = "scons" \
    -o ${PACKAGE:0:7} = "devenv_"  \
    -o $PACKAGE = "gcc"  \
    -o $PACKAGE = "afwdata" \
    -o $PACKAGE = "astrometry_net_data" \
    -o $PACKAGE = "isrdata"  \
    -o $PACKAGE = "auton"  \
    -o $PACKAGE = "ssd"  \
    -o ${PACKAGE:0:4} = "lsst" ]; then 
    print "Selected packages are not tested via trunk-vs-trunk, $PACKAGE is one of them"
    exit 0
fi

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
step "Sequence Dependency Chain"

CUR_COUNT=0
python /home/buildbot/scripts/orderDependents.py $PACKAGE > /tmp/tVtList.tmp

print "Order of dependency processing"
while read LINE; 
do
    print "   $CUR_COUNT  $LINE"
    (( CUR_COUNT++ ))
done < "/tmp/tVtList.tmp"



CUR_COUNT=0
while read CUR_PACKAGE CUR_VERSION CUR_DETRITUS
do
    cd $WORK_PWD
    #++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    step "Install dependency: $CUR_PACKAGE for $PACKAGE build"

    # -- Process external or special-case packages  via lsstpkg --
    package_is_external ${CUR_PACKAGE}
    if [ $? = 0 ]; then
        print "Installing external package: $CUR_PACKAGE $CUR_VERSION"

        if [ `eups list $CUR_PACKAGE $CUR_VERSION | wc -l` = 0 ]; then
            INSTALL_CMD="lsstpkg install $CUR_PACKAGE $CUR_VERSION"
            pretty_execute $INSTALL_CMD
            if [ $RETVAL != 0 ]; then
                print "Failed to install $CUR_PACKAGE $CUR_VERSION with lsstpkg."
                exit 1
            else
                print "Dependency: $CUR_PACKAGE, successfully installed."
            fi
        fi
        setup -j $CUR_PACKAGE $CUR_VERSION
        if [ $RETVAL != 0 ]; then
            print "Failed to setup dependency: $CUR_PACKAGE $CUR_VERSION."
            exit 1
        fi
        print "Dependency: $CUR_PACKAGE $CUR_VERSION, successfully installed."
        continue
    fi


    # -- Process special lsst packages  neither external nor svn-able --
    if [ ${CUR_PACKAGE:0:5} = "scons" \
        -o ${CUR_PACKAGE:0:7} = "devenv_"  \
        -o $CUR_PACKAGE = "gcc"  \
        -o $CUR_PACKAGE = "afwdata" \
        -o $CUR_PACKAGE = "astrometry_net_data" \
        -o $CUR_PACKAGE = "isrdata"  \
        -o $CUR_PACKAGE = "auton"  \
        -o $CUR_PACKAGE = "ssd"  \
        -o ${CUR_PACKAGE:0:4} = "lsst" ]; then 
        # Attempt setup of named package/version; don't exit if failure occurs
        setup -j $CUR_PACKAGE $CUR_VERSION
        if [ $? = 0 ]; then
            print "Special-case dependency: $CUR_PACKAGE $CUR_VERSION  successfully installed"
        else
            print "Special-case dependency: $CUR_PACKAGE $CUR_VERSION  not available. Continuing without it."
        fi
        continue
    fi

    # -- Process lsst packages --
    #First a little adjustment of naming: mops -> mops_nightmops
    if [ "$CUR_PACKAGE" = "mops" ]; then
        CUR_PACKAGE="mops_nightmops"
    fi

    # package is internal and should be built from trunk
    lookup_svn_trunk_revision $CUR_PACKAGE
    PLAIN_VERSION="$RET_REVISION"
    RET_REVISION="svn$RET_REVISION"
    SVN_URL=$RET_SVN_URL
    REVISION=$RET_REVISION

    print "Internal package: $CUR_PACKAGE will be built from trunk version: $PLAIN_VERSION"
    
    mkdir -p svn
    SVN_LOCAL_DIR=svn/${CUR_PACKAGE}_$PLAIN_VERSION
    
# RAA #
#        #_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#
#  F I X    Following should, if nec: 1 unsetup, 2 eups remove, 3 rmdir  F I X
#        #_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#
# RAA #
    # if force, remove existing package
    if [ "$FORCE" -a -d $SVN_LOCAL_DIR ]; then
        lookup_svn_revision $SVN_LOCAL_DIR
        print "Remove existing $CUR_PACKAGE $REVISION"
        if [ `eups list $CUR_PACKAGE $REVISION | grep Setup | wc -l` = 1 ]; then
            unsetup -j $CUR_PACKAGE $REVISION
        fi
        pretty_execute "eups remove -N $CUR_PACKAGE $REVISION"
        # remove svn dir, to force re-checkout
        pretty_execute "rm -rf $SVN_LOCAL_DIR"
    fi
    
    if [ ! -d $SVN_LOCAL_DIR ]; then
        step "Check out $CUR_PACKAGE $REVISION from $SVN_URL"
        SVN_COMMAND="svn checkout $SVN_URL $SVN_LOCAL_DIR "
    else
        step "Update $CUR_PACKAGE $REVISION from svn"
        SVN_COMMAND="svn update $SVN_LOCAL_DIR "
    fi
    verbose_execute $SVN_COMMAND
    if [ $RETVAL != 0 ]; then
        print "svn checkout or update failed; is $CUR_PACKAGE $REVISION a valid version?"
        exit 1
    fi


    # -------------------------------
    # -- setup for a package build --
    # -------------------------------
    
    FULL_PATH_TO_SVN_LOCAL_DIR="LOCAL:$WORK_PWD/$SVN_LOCAL_DIR"
    pretty_execute "setup -j $CUR_PACKAGE $FULL_PATH_TO_SVN_LOCAL_DIR"
    
    # ----------------------------------------------------------------
    # -- Rest of work is done within the package's source directory --
    # ----------------------------------------------------------------
    cd $SVN_LOCAL_DIR > /dev/null
    
    pretty_execute "eups list -s # AFTER setups"
    pretty_execute "eups list $CUR_PACKAGE"
    
    #RAA#debug "Clean up previous build attempt in directory"
    #RAA#quiet_execute scons -c
    scons_tests $CUR_PACKAGE
    pretty_execute "scons opt=3 install $SCONS_TESTS"
    SCONS_EXIT=$RETVAL
    if [ $SCONS_EXIT != 0 ]; then
        print "Install/test failed: $CUR_PACKAGE $REVISION"
        FAILED_INSTALL=true
    fi
    
    # preserve logs
    LOG_FILE="config.log"
    pretty_execute pwd
    if [ "$LOG_DEST" -a "(" "$FAILED_INSTALL" -o "$LOG_SUCCESS" ")" ]; then
        if [ -f "$LOG_FILE" ]; then
            copy_log ${CUR_PACKAGE}_$REVISION/$LOG_FILE $LOG_FILE $LOG_DEST_HOST $LOG_DEST_DIR ${CUR_PACKAGE}/$REVISION $LOG_URL
        else
            print "No $LOG_FILE present."
        fi
    else
        if [ -f "$LOG_FILE" ]; then
            print "Not preserving config.log."
        else
            print "No config.log generated."
        fi
    fi
    
    
    if [  ! $FAILED_INSTALL ]; then
        # ----------------------------
        # -- check for failed tests --
        # ----------------------------
        step "Checking for failed tests"
        if [ -d tests ]; then
            FAILED_COUNT=`find tests -name "*.failed" | wc -l`
            if [ $FAILED_COUNT != "0" ]; then
                print "Some tests failed:"
                pretty_execute -anon 'find tests -name "*.failed"'
                # cat .failed files to stdout
                for FAILED_FILE in `find tests -name "*.failed"`; do
                    pretty_execute "cat $FAILED_FILE"
                done
                FAILED_INSTALL=true
            else
                print "All tests succeeded in $CUR_PACKAGE"
            fi
        else
            print "No tests found in $CUR_PACKAGE"
        fi
    fi
    
    if [ $FAILED_INSTALL ]; then
        # -----------------------------------------------------------------------
        # -- return to primary work directory so can 'rm' the source directory --
        # -----------------------------------------------------------------------
        cd $WORK_PWD

        print "Installation of $CUR_PACKAGE $REVISION failed."
        print "Unable to build trunk-vs-trunk version of $PACKAGE due to failed build of dependency: $CUR_PACKAGE $REVISION ."
        exit 1
    fi

    # -------------------------------------------------
    # -- Loop around to next entry in dependency list --
    # -------------------------------------------------
    (( CUR_COUNT++ ))

done < "/tmp/tVtList.tmp"


print "Successfully built trunk-vs-trunk version of $PACKAGE"
exit 0
