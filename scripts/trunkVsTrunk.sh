#! /bin/bash
# install a requested package from version control, and recursively
# ensure that its minimal dependencies are installed likewise


#***********************************************************************
#        T B D    T B D   T B D   T B D   T B D   T B D
# In order to get an accurate dependency able, ALL trunk svn directories
# must be extracted and 'setup -j LOCAL:<name>'  so that eups can deduce
# the dependencies from the source tree.  Only then should the build
# of the dependencies commence in the order specified.
#
# The current version will not pick up a new dependency listed in the
# trunk version of one of the  dependent 'eups declared' packages.
#        T B D    T B D   T B D   T B D   T B D   T B D
#***********************************************************************


usage() {
#80 cols  ................................................................................
    echo "Usage: $0 [options] package"
    echo "Install a requested package from version control (trunk), and recursively"
    echo "ensure that its dependencies are also installed from version control."
    echo
    echo "Options (must be in this order):"
    echo "          -verbose: print out extra debugging info"
    echo "            -force: if the package is already installed, re-install it"
    echo " -dont_log_success: if specified, only save logs if install fails"
    echo "  -log_dest <dest>: scp destination for config.log,"
    echo "                    for example \"buildbot@master:/var/www/html/logs\""
    echo "    -log_url <url>: URL prefix for the log destination,"
    echo "                    for example \"http://master/logs/\""
    echo "         -no_tests: only build package, don't run tests"
}
source /lsst/stacks/default/loadLSST.sh
source ${0%/*}/build_functions.sh

DEBUG=debug
DEV_SERVER="lsstdev.ncsa.uiuc.edu"
SVN_SERVER="svn.lsstcorp.org"
WEB_ROOT="/var/www/html/doxygen"

#Exclude known persistent test failures until they are fixed or removed
#    sdqa/tests/testSdqaRatingFormatter.py 
SKIP_THESE_TESTS="| grep -v testSdqaRatingFormatter.py "

# ---------------
# -- Functions --
# ---------------
# -- Alter eups name not corresponding to directory path convention --
# $1 = eups package name
# return ADJUSTED_NAME in LSST standard so its svn directory name is derived OK
adjustBadEupsName() {
    #  A little adjustment of bad package naming:  
    #  at the moment, only one:  mops -> mops_nightmops
    if [ "$1" = "mops" ]; then
        ADJUSTED_NAME="mops_nightmops"
    else
        ADJUSTED_NAME="$1"
    fi
}


# -- Some LSST internal packages should never be built from trunk --
# $1 = eups package name
# return 0 if a special LSST package which should be considered external
package_is_special() {
    if [ "$1" = "" ]; then
        print "No package name provided for internal specialness check. See LSST buildbot developer."
        exit 1
    fi
    local SPCL_PACKAGE="$1"

    if [ ${SPCL_PACKAGE:0:5} = "scons" \
        -o ${SPCL_PACKAGE:0:7} = "devenv_"  \
        -o $SPCL_PACKAGE = "gcc"  \
        -o $SPCL_PACKAGE = "afwdata" \
        -o $SPCL_PACKAGE = "astrometry_net_data" \
        -o $SPCL_PACKAGE = "isrdata"  \
        -o $SPCL_PACKAGE = "auton"  \
        -o $SPCL_PACKAGE = "ssd"  \
        -o $SPCL_PACKAGE = "base"  \
        -o ${SPCL_PACKAGE:0:4} = "lsst" ]; then 
        return 0
    else
        return 1
    fi
}
# -- setup package's svn directory in preparation for the build --
# $1 = adjusted eups package name
# return:  0, if svn checkout/update occured withuot error; 1, otherwise.
# RET_REVISION
# SVN_URL
# REVISION 
# SVN_LOCAL_DIR

prepareSvnDir() {

    # ------------------------------------------------------------
    # -- NOTE:  most variables in this function are global!  NOTE--
    # ------------------------------------------------------------

    if [ "$1" = "" ]; then
        print "No package name for svn extraction. See LSST buildbot developer."
        exit 1
    fi

    local SVN_PACKAGE=$1 

    # package is internal and should be built from trunk
    lookup_svn_trunk_revision $SVN_PACKAGE
    local PLAIN_VERSION="$RET_REVISION"
    RET_REVISION="svn$RET_REVISION"
    SVN_URL=$RET_SVN_URL
    REVISION=$RET_REVISION

    print "Internal package: $SVN_PACKAGE will be built from trunk version: $PLAIN_VERSION"
    
    mkdir -p svn
    SVN_LOCAL_DIR="svn/${SVN_PACKAGE}_${PLAIN_VERSION}"
    
    # if force, remove existing package
    if [ "$FORCE" -a -d $SVN_LOCAL_DIR ]; then
        lookup_svn_revision $SVN_LOCAL_DIR
        print "Remove existing $SVN_PACKAGE $REVISION"
        if [ `eups list $SVN_PACKAGE $REVISION | grep Setup | wc -l` = 1 ]; then
            unsetup -j $SVN_PACKAGE $REVISION
        fi
        pretty_execute "eups remove -N $SVN_PACKAGE $REVISION"
        # remove svn dir, to force re-checkout
        pretty_execute "rm -rf $SVN_LOCAL_DIR"
    fi
    
    if [ ! -d $SVN_LOCAL_DIR ]; then
        step "Check out $SVN_PACKAGE $REVISION from $SVN_URL"
        local SVN_COMMAND="svn checkout $SVN_URL $SVN_LOCAL_DIR "
    else
        step "Update $SVN_PACKAGE $REVISION from svn"
        local SVN_COMMAND="svn update $SVN_LOCAL_DIR "
    fi
    verbose_execute $SVN_COMMAND
}



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

if [ "$1" = "-no_tests" ]; then
    DO_TESTS=1
    shift 1
else
    DO_TESTS=0
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

package_is_special $PACKAGE
if [ $? = 0 ]; then
    print "Selected packages are not tested via trunk-vs-trunk, $PACKAGE is one of them"
    exit 0
fi

adjustBadEupsName $PACKAGE
PACKAGE=$ADJUSTED_NAME

prepareSvnDir $PACKAGE
if [ $RETVAL != 0 ]; then
    print "$PACKAGE svn checkout or update failed; contact the LSST buildbot developer"
    exit 1
fi

#***********************************************************************
#        T B D    T B D   T B D   T B D   T B D   T B D
# In order to get an accurate dependency able, ALL trunk svn directories
# must be extracted and 'setup -j LOCAL:<name>'  so that eups can deduce
# the dependencies from the source tree.  Only then should the build
# of the dependencies commence in the order specified.
#
# The current code segment below will not pick up a new dependency listed 
# in the trunk version of one of the  dependent 'eups declared' packages.
#        T B D    T B D   T B D   T B D   T B D   T B D
#***********************************************************************

# -- setup primary package in prep for dependency list generation
FULL_PATH_TO_SVN_LOCAL_DIR="LOCAL:$WORK_PWD/$SVN_LOCAL_DIR"
pretty_execute "setup -j $PACKAGE $FULL_PATH_TO_SVN_LOCAL_DIR"


#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
step "Sequence $PACKAGE Dependency Chain"

#TMP_FILE=`mktemp /tmp/buildbot_tVt.XXXXXXXXXX`
TMP_FILE="$WORK_PWD/buildbot_tVt_temp"
`cp /dev/null $TMP_FILE`
if [ $? != 0 ]; then
   print "Unable to create temporary file for dependency sequencing."
   print "Test of $PACKAGE failed before it started."
   exit 1
fi
python ${0%/*}/orderDependents.py $PACKAGE > $TMP_FILE

COUNT=0
while read LINE; 
do
    print "   $COUNT  $LINE"
    (( COUNT++ ))
done < $TMP_FILE


while read CUR_PACKAGE CUR_VERSION CUR_DETRITUS; do
    cd $WORK_PWD
    #++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    step "Install dependency $CUR_PACKAGE for $PACKAGE build"

    # -- Process external or special-case packages  via lsstpkg --
    package_is_external ${CUR_PACKAGE}
    if [ $? = 0 ]; then
        print "Installing external package: $CUR_PACKAGE $CUR_VERSION"
        if [ $CUR_VERSION != "Current" ]; then
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
        else
            # if dependency needs just needs 'current', go with it
            if [ `eups list $CUR_PACKAGE | wc -l` = 0 ]; then
                print "Failed to setup dependency: $CUR_PACKAGE."
                print "An 'lsstpkg install' version was not provided."
                exit 1
            fi
            CUR_VERSION=""
        fi
        pretty_execute "setup -j $CUR_PACKAGE $CUR_VERSION"
        if [ $RETVAL != 0 ]; then
            print "Failed to setup dependency: $CUR_PACKAGE $CUR_VERSION."
            exit 1
        fi
        print "Dependency: $CUR_PACKAGE $CUR_VERSION, successfully installed."
        continue
    fi


    # -- Process special lsst packages  neither external nor svn-able --
    package_is_special $CUR_PACKAGE
    if [ $? = 0 ]; then
        # Attempt setup of named package/version; don't exit if failure occurs
        setup -j $CUR_PACKAGE $CUR_VERSION
        if [ $? = 0 ]; then
            print "Special-case dependency: $CUR_PACKAGE $CUR_VERSION  successfully installed"
        else
            print "Special-case dependency: $CUR_PACKAGE $CUR_VERSION  not available. Continuing without it."
        fi
        continue
    fi

    # -----------------------------------
    # -- Prepare SVN directory for build --
    # -----------------------------------

    adjustBadEupsName $CUR_PACKAGE
    CUR_PACKAGE=$ADJUSTED_NAME

    prepareSvnDir $CUR_PACKAGE
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
    cd $SVN_LOCAL_DIR 
    
    GOOD_BUILD="0"
    pretty_execute "eups list -s"
    #pretty_execute "eups list $CUR_PACKAGE"
    
    #RAA#debug "Clean up previous build attempt in directory"
    #RAA#quiet_execute scons -c
    if [ $DO_TESTS = 0 ] ; then
        scons_tests $CUR_PACKAGE
    else
        SCONS_TESTS=""
    fi
    pretty_execute "scons opt=3 install $SCONS_TESTS"
    if [ $RETVAL != 0 ]; then
        print "Install/test failed: $CUR_PACKAGE $REVISION"
        GOOD_BUILD=1
    fi

    if [ $GOOD_BUILD = 0 -a $DO_TESTS = 0 ]; then
        # ----------------------------
        # -- check for failed tests --
        # ----------------------------
        # but exclude known persistent test failures....
        #      they should be removed from unit test suite

        step "Checking for failed tests"
        if [ -d tests ]; then
            FAILED_COUNT=`eval "find tests -name \"*.failed\" $SKIP_THESE_TESTS | wc -l"`
            if [ $FAILED_COUNT != 0 ]; then
                print "One or more required tests failed:"
                pretty_execute -anon 'find tests -name "*.failed"'
                # cat .failed files to stdout
                for FAILED_FILE in `find tests -name "*.failed"`; do
                    pretty_execute "cat $FAILED_FILE"
                done
                GOOD_BUILD="1"
            else
                print "All required tests succeeded in $CUR_PACKAGE"
            fi
        else
            print "No tests found in $CUR_PACKAGE"
        fi
    fi
    
    if [ $GOOD_BUILD = 1 ]; then
        # preserve config log for failure info
        LOG_FILE="config.log"
        pretty_execute pwd
        if [ "$LOG_DEST" -a "(" "$GOOD_BUILD" = "1" -o "$LOG_SUCCESS" ")" ]; then
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

        # -- return to primary work directory  --
        # --               later, possibly 'rm' source directory --
        cd $WORK_PWD

        print "Installation of $CUR_PACKAGE $REVISION failed."
        print "Unable to build trunk-vs-trunk version of $PACKAGE due to failed build of dependency: $CUR_PACKAGE $REVISION ."
        exit 1
    fi

    # -------------------------------------------------
    # -- Loop around to next entry in dependency list --
    # -------------------------------------------------

done < "$TMP_FILE"

if [ $DO_TESTS = 0 ]; then
    print "Successfully built and tested trunk-vs-trunk version of $PACKAGE"
else
    print "Successfully built (but not tested) trunk-vs-trunk version of $PACKAGE"
fi
exit 0
