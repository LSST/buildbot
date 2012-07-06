#! /bin/bash
# install a requested package from version control, and recursively
# ensure that its minimal dependencies are installed likewise

DEBUG=debug
DEV_SERVER="lsstdev.ncsa.uiuc.edu"
SCM_SERVER="git.lsstcorp.org"
WEB_ROOT="/var/www/html/doxygen"


#Exclude known persistent test failures until they are fixed or removed
#   Code Developer should install into tests/SConscript:
#       ignoreList=["testSdqaRatingFormatter.py"]
#       tests = lsst.tests.Control(env, ignoreList=ignoreList, verbose=True)
# If not use e.g.    SKIP_THESE_TESTS="| grep -v testSdqaRatingFormatter.py "
SKIP_THESE_TESTS=""

source ${0%/*}/gitConstants.sh
source ${0%/*}/build_functions.sh
source ${0%/*}/gitBuildFunctions.sh
source ${0%/*}/gitBuildFunctions2.sh

# -------------------
# -- get arguments --
# -------------------

options=$(getopt -l verbose,boot,force,dont_log_success,log_dest:,log_url:,builder_name:,build_number:,slave_devel:,production,no_tests,parallel:,package:,step_name:,on_demand,on_change -- "$@")

LOG_SUCCESS=0
BUILDER_NAME=""
BUILD_NUMBER=0
PRODUCTION_RUN=1
DO_TESTS=0
PARALLEL=2
STEP_NAME="unknown"
ON_DEMAND_BUILD=1
ON_CHANGE_BUILD=1
ONE_PASS_BUILD=1
SCM_PACKAGE=""
while true
do
    case $1 in
        --verbose) VERBOSE=true; shift;;
        --debug) VERBOSE=true; shift;;
        --force) FORCE=true; shift;;
        --dont_log_success) LOG_SUCCESS=1; shift;;
        --log_dest) 
                LOG_DEST=$2; 
                LOG_DEST_HOST=${LOG_DEST%%\:*}; # buildbot@master
                LOG_DEST_DIR=${LOG_DEST##*\:};  # /var/www/html/logs
                shift 2;;
        --log_url) LOG_URL=$2; shift 2;;
        --builder_name)
                BUILDER_NAME=$2; 
                print "BUILDER_NAME: $BUILDER_NAME"
                shift 2;;
        --build_number)
                BUILD_NUMBER=$2;
                print "BUILD_NUMBER: $BUILD_NUMBER"
                shift 2;;
        --production) PRODUCTION_RUN=0; shift 1;;
        --no_tests) DO_TESTS=1; shift 1;;
        --parallel) PARALLEL=$2; shift 2;;
        --package) PACKAGE=$2; shift 2;;
        --step_name) STEP_NAME=$2; shift 2;;
        --on_demand) ON_DEMAND_BUILD=0; ONE_PASS_BUILD=0; shift 1;;
        --on_change) ON_CHANGE_BUILD=0; ONE_PASS_BUILD=0; shift 1;;
        *) echo "parsed options; arguments left are: $*"
             break;;
    esac
done


echo "STEP_NAME = $STEP_NAME"
if [ "$STEP_NAME" = "unknown" ]; then
    FAIL_MSG="Missing input argument '--step_name',  build step name must be specified."
    emailFailure "Unknown"  "$BUCK_STOPS_HERE"
    exit 1
fi

if [ ! -d $LSST_DEVEL ] ; then
    FAIL_MSG="LSST_DEVEL: $LSST_DEVEL, was not passed as environment variable and thus does not exist."
    emailFailure "Unknown" "$BUCK_STOPS_HERE"
    exit 1
fi

# Acquire Root PACKAGE Name; OnChange's version extracted from gitrepos addr
if [ "$1" = "" ]; then
    FAIL_MSG="Missing input argument: '--package', package name must be supplied."
    emailFailure "Unknown" "$BUCK_STOPS_HERE"
    exit 1
elif [ "$ON_CHANGE_BUILD" = "1" ]; then
    PACKAGE="$1"
else
    # need to convert input param from repository name to package name
    scm_url_to_package "$1"
    if [ "$SCM_PACKAGE" != "" ]; then
        PACKAGE="$SCM_PACKAGE"
        print "OnChange sets: PACKAGE:$PACKAGE:    STEP_NAME:  $STEP_NAME"
    else
        FAIL_MSG="Change triggered builds require a valid url to the package repository as input.\n$1 is not formatted correctly."
        emailFailure "$1" "$BUCK_STOPS_HERE"
        exit 1
    fi
fi

print "PACKAGE: $PACKAGE    STEP_NAME:  $STEP_NAME  SCM_PACKAGE: $SCM_PACKAGE"


WORK_PWD=`pwd`

#Allow developers to access slave directory
umask 002

source $LSST_STACK"/loadLSST.sh"

#*************************************************************************
#First action...rebuild the $LSST_DEVEL cache
pretty_execute "eups admin clearCache -Z $LSST_DEVEL"
pretty_execute "eups admin buildCache -Z $LSST_DEVEL"

#*************************************************************************
step "Determine if $PACKAGE will be tested"

package_is_special $PACKAGE
if [ $? = 0 ]; then
    print "Selected packages are not tested, $PACKAGE is one of them"
    exit 0
fi
package_is_external $PACKAGE
if [ $? = 0 ]; then 
    print "External packages are not tested, $PACKAGE is one of them."
    exit 0
fi


# this gets $EXTERNAL_DEPS, $INTERNAL_DEPS, $RET_REVISION, $REVISION 
# and $SCM_LOCAL_DIR set for $PACKAGE

queryPackageInfo $PACKAGE

if [ -f $WORK_PWD/git/$PACKAGE/$REVISION/BUILD_OK ]; then
    print "PACKAGE: $PACKAGE $REVISION has BUILD_OK flag and will not be rebuilt."
    exit 0
else
    print "PACKAGE: $PACKAGE $REVISION does not have BUILD_OK flag and will be rebuilt."
fi

PACKAGE_SCM_REVISION=$RET_REVISION
[[ "$DEBUG" ]] && print "PACKAGE: $PACKAGE PACKAGE_SCM_REVISION: $PACKAGE_SCM_REVISION"

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
step "List build dependency tree for $PACKAGE"

cat $EXTERNAL_DEPS
cat $INTERNAL_DEPS

while read PACKAGE_DEPTH CUR_PACKAGE CUR_VERSION; do
    cd $WORK_PWD
    step "Setup external dependencies for $CUR_PACKAGE"
    while read EX_CUR_PACKAGE EX_CUR_VERSION; do
        pretty_execute "setup $EX_CUR_PACKAGE $EX_CUR_VERSION"
        if [ $? != 0 ]; then
            FAIL_MSG="Failed in eups-set of $EX_CUR_PACKAGE @ $EX_CUR_VERSION during first pass at dependency installation."
        fi
    done < "$EXTERNAL_DEPS"



    echo "EUPS listing of setup packages:"
    eups list -s

    step "Checking $CUR_PACKAGE $CUR_VERSION status"
    # ---------------------------------------------------------------------
    # --  BLOCK1 -  this assumes that when NoTest is taken, that only a 
    # --            compilation is required and not a reload to check 
    # --            altered lib signatures or dependencies.
    # ---------------------------------------------------------------------
    print "cur_package is $CUR_PACKAGE   revision is $CUR_VERSION"
    [[ "$DEBUG" ]] && print "git/$CUR_PACKAGE/$CUR_VERSION/BUILD_OK"

    if  [ -f "git/$CUR_PACKAGE/$CUR_VERSION/BUILD_OK" ] ; then
        [[ "$DEBUG" ]] && print "Local src directory is marked BUILD_OK"
        # srp - jan 24 2012 - change next line to get current version which
        # is already installed.
        #pretty_execute "setup -j  $CUR_PACKAGE $CUR_VERSION"
        pretty_execute "setup -k -t current $CUR_PACKAGE"
        print "after setup in OK check, RETVAL = $RETVAL"
        if [ $RETVAL = 0 ] ; then
            print "Package/revision is already completed. Skipping build."
            print "using this version:"
            pretty_execute "eups list -s $CUR_PACKAGE"
            continue
        fi
    else
        print "Local src directory is NOT marked BUILD_OK, so we need to check if this package can be built."
    fi

    if [ "$ONE_PASS_BUILD" == "1" ]; then
        UNRELEASED_PACKAGE=`grep -w $CUR_PACKAGE $WORK_PWD/unreleased.txt`

        if [ "$UNRELEASED_PACKAGE" != "" ]; then
            echo "This is probably a new unreleased package, so we need to build it."
        elif [ "$CUR_PACKAGE" == $STEP_NAME ]; then
            echo "This is the target package for building.  Continuing."
        elif [ -e $WORK_PWD/git/$CUR_PACKAGE/$CUR_VERSION/BUILD_FAIL ] ; then 
            FAIL_MSG="$CUR_PACKAGE failed to successfully build earlier in the one-pass ordering.\n\n"
            emailFailure "$STEP_NAME" "$BUCK_STOPS_HERE"
            exit 2
        else 
            FAIL_MSG="$CUR_PACKAGE is a dependent package of $STEP_NAME that was not marked as pre-built.\nPossibly '~/RHEL6/etc/LsstStackManifest.txt' is out of order or missing a dependency declaration.\n\nBetter check which is the case."
            emailFailure "$STEP_NAME" "$BUCK_STOPS_HERE"
            clear_blame_data
        fi
    fi

    step "Building $CUR_PACKAGE $CUR_VERSION"

    # ----------------------------------------------------------------
    # -- Rest of build work is done within the package's source directory --
    # ----------------------------------------------------------------
    BUILD_ROOT=$PWD
    cd $WORK_PWD/git/$CUR_PACKAGE/$CUR_VERSION
    print $PWD

    pretty_execute "setup -r . -k "
    pretty_execute "eups list -s"
    saveSetupScript $BUILD_ROOT $CUR_PACKAGE $BUILD_NUMBER $PWD

    BUILD_STATUS=0
    unset BUILD_ERROR

    # compile lib and build docs; then test executables; then install.
    scons_tests $CUR_PACKAGE
    pretty_execute "scons -j $PARALLEL opt=3 lib python doc"
    if [ $RETVAL != 0 ]; then
        BUILD_STATUS=2
        BUILD_ERROR="failure of initial 'scons -j $PARALLEL opt=3 lib python' build ($BUILD_STATUS)."
        print_error $BUILD_ERROR
    elif [ $DO_TESTS = 0 -a "$SCONS_TESTS" = "tests" -a -d tests ]; then 
        # Built libs & doc OK, now test executables (examples and tests) 

	# don't run these in parallel, because some tests depend on other
	# binaries to be built, and there's a race condition that will cause
	# the tests to fail if they're not built before the test is run.
        # RAA 23 Feb 2012 -- ctrl_sched/tests has race condition using -j#  
        if [ "$CUR_PACKAGE" = "ctrl_sched"  -o "$CUR_PACKAGE" = "ctrl_events" ] ; then
            pretty_execute "scons  opt=3 lib tests examples"
        else
            pretty_execute "scons -j $PARALLEL opt=3 lib tests examples"
        fi
        TESTING_RETVAL=$RETVAL
        FAILED_COUNT=`eval "find tests -name \"*.failed\" $SKIP_THESE_TESTS | wc -l"`
        if [ $FAILED_COUNT != 0 ]; then
            print_error "One or more required tests failed:"
            pretty_execute -anon 'find tests -name "*.failed"'
            # cat .failed files to stdout
            for FAILED_FILE in `find tests -name "*.failed"`; do
                echo "================================================" 
                echo "Failed unit test: $PWD/$FAILED_FILE" 
                cat $FAILED_FILE
                echo "================================================"
            done
            BUILD_STATUS=4
            BUILD_ERROR="failure of 'scons -j $PARALLEL opt=3 lib tests examples' build ($BUILD_STATUS)."
            print_error $BUILD_ERROR
        elif [ $TESTING_RETVAL != 0 ]; then
            # Probably failed in examples since the tests didn't report failure
            BUILD_STATUS=5
            BUILD_ERROR="failure of 'scons -j $PARALLEL opt=3 lib tests examples' build ($BUILD_STATUS)."
            print_error $BUILD_ERROR
        else   # Built libs & doc OK, ran executables OK, now eups-install
            pretty_execute "scons  version=$CUR_VERSION+$BUILD_NUMBER opt=3 lib install current declare"
            if [ $RETVAL != 0 ]; then
                BUILD_STATUS=3
                BUILD_ERROR="failure of install: 'scons  version=$CUR_VERSION+$BUILD_NUMBER opt=3 lib install current declare' build ($BUILD_STATUS)."
                print_error $BUILD_ERROR
            else
                print "Success of Compile/Load/Test/Install: $CUR_PACKAGE $CUR_VERSION"
                eups declare -t SCM $CUR_PACKAGE $CUR_VERSION+$BUILD_NUMBER
                if [ $? != 0 ]; then
                    print_error "WARNING: failure setting SCM tag on build product."
                else
                    print "Success of SCM tag on: $CUR_PACKAGE $CUR_VERSION"
                fi
            fi
        fi
    else  # Built libs & doc OK, no tests wanted|available, now eups-install
            pretty_execute "scons version=$CUR_VERSION+$BUILD_NUMBER opt=3 lib install current declare python"
            if [ $RETVAL != 0 ]; then
                BUILD_STATUS=1
                BUILD_ERROR="failure of install: 'scons version=$CUR_VERSION+$BUILD_NUMBER opt=3 lib install current declare python' build ($BUILD_STATUS)."
                print_error $BUILD_ERROR
            fi
            print "Success during Compile/Load/Install with-tests: $CUR_PACKAGE $CUR_VERSION"
            eups declare -t SCM $CUR_PACKAGE $CUR_VERSION+$BUILD_NUMBER
            if [ $? != 0 ]; then
                print_error "WARNING: failure setting SCM tag on build product."
            else
                print "Success of SCM tag on: $CUR_PACKAGE $CUR_VERSION"
            fi
    fi

    print "BUILD_STATUS status after test failure search: $BUILD_STATUS"
    # Archive log if explicitly requested on success and always on failure.
    if [ "$BUILD_STATUS" -ne "0" ]; then
        # preserve config log 
        LOG_FILE="config.log"
        pretty_execute pwd
        if [ "$LOG_DEST" ]; then
            if [ -f "$LOG_FILE" ]; then
                copy_log ${CUR_PACKAGE}_$CUR_VERSION/$LOG_FILE $LOG_FILE $LOG_DEST_HOST $LOG_DEST_DIR ${CUR_PACKAGE}/$CUR_VERSION $LOG_URL
            else
                print_error "WARNING: No $LOG_FILE present."
            fi
        else
            print_error "WARNING: No archive destination provided for log file."
        fi
    fi

    #----------------------------------------------------------
    # -- return to primary work directory  --
    #----------------------------------------------------------
    cd $WORK_PWD

    # Time to exit due to build failure of a dependency
    if [ "$BUILD_STATUS" -ne "0" ]; then
        FAIL_MSG="\nBuildbot failed to build $PACKAGE due to an error building dependency: $CUR_PACKAGE.\n\nDependency: $CUR_PACKAGE (version: $CUR_VERSION) error:\n$BUILD_ERROR\n"
        # Get Email List for Package Owners & Blame list
        fetch_package_owners $CUR_PACKAGE
        fetch_blame_data $SCM_LOCAL_DIR $WORK_PWD 
        if [ "$CUR_PACKAGE" != "$PACKAGE" ]; then
           SEND_TO="$BUCK_STOPS_HERE"
        else
           SEND_TO="$BLAME_EMAIL, $PACKAGE_OWNERS"
        fi
        #emailFailure "$STEP_NAME" "$SEND_TO" 
        emailFailure "$CUR_PACKAGE" "$SEND_TO" 
        clear_blame_data

        #   Following only necessary if failed during scons-install step
        if [ "`eups list -s $CUR_PACKAGE $CUR_VERSION 2> /dev/null | grep $CUR_VERSION | wc -l`" != "0" ]; then
            pretty_execute "setup -u -j $CUR_PACKAGE $CUR_VERSION"
        fi
        if [ "`eups list -c $CUR_PACKAGE $CUR_VERSION  &> /dev/null | grep $CUR_VERSION | wc -l`" != "0" ]; then
            pretty_execute "eups undeclare -c $CUR_PACKAGE $CUR_VERSION"
        fi
        print_error "Exiting since $CUR_PACKAGE failed to build/install successfully"
        echo touch $WORK_PWD/git/$CUR_PACKAGE/$CUR_VERSION/BUILD_FAIL
        touch $WORK_PWD/git/$CUR_PACKAGE/$CUR_VERSION/BUILD_FAIL

        if [ "$CUR_PACKAGE" != "$PACKAGE" ] ; then
            exit 2
        else
            exit 1
        fi
    fi

    # For production build, setup each successful install 
    print "-------------------------"
    # srp - jan 24 2012 -  use current version which is already installed.
    setup -t current $CUR_PACKAGE
    if [ $? != 0 ]; then
        print_error "WARNING: unable to complete setup of installed $CUR_PACKAGE $CUR_VERSION. Continuing with package setup in local directory."
    fi
    # srp - jan 24 2012 - use current version which is already installed.
    eups list -t current -v $CUR_PACKAGE
    print "-------------------------"
    echo touch $WORK_PWD/git/$CUR_PACKAGE/$CUR_VERSION/BUILD_OK
    touch $WORK_PWD/git/$CUR_PACKAGE/$CUR_VERSION/BUILD_OK
    retval=$? 
    if [ $retval == 0 ]; then
        rm -f $WORK_PWD/git/$CUR_PACKAGE/$CUR_VERSION/NEEDS_BUILD
        rm -f $WORK_PWD/git/$CUR_PACKAGE/$CUR_VERSION/BUILD_FAIL
    else
        print_error "WARNING: unable to set flag: $WORK_PWD/git/$CUR_PACKAGE/$CUR_VERSION/BUILD_OK; this source directory will be rebuilt on next use." 
    fi
    echo "EUPS_PATH is $EUPS_PATH"
    echo "Finished working with $CUR_PACKAGE $CUR_VERSION"

# -------------------------------------------------
# -- Loop around to next entry in dependency list --
# -------------------------------------------------
done < "$INTERNAL_DEPS"

if [ $DO_TESTS = 0 ]; then
    print "Successfully built and tested $PACKAGE"
else
    print "Successfully built, but not tested, $PACKAGE"
fi
exit 0
