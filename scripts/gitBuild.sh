#! /bin/bash
# install a requested package from version control, and recursively
# ensure that its minimal dependencies are installed likewise

DEV_SERVER="lsstdev.ncsa.uiuc.edu"
SCM_SERVER="git.lsstcorp.org"
WEB_ROOT="/var/www/html/doxygen"

FAILED_TESTS_LOG="FailedTests.log"

BUILD_FAILURE_BLAME="BlameNotification.list"

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

options=$(getopt -l debug,boot,dont_log_success,log_dest:,log_url:,builder_name:,build_number:,slave_devel:,no_tests,parallel:,step_name:,on_demand,on_change -- "$@")

BUILDER_NAME=""
BUILD_NUMBER=0
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
        --debug) DEBUG=true; shift;;
        --builder_name) BUILDER_NAME=$2; shift 2;;
        --build_number) BUILD_NUMBER=$2; shift 2;;
        --log_dest) 
                LOG_DEST=$2; 
                LOG_DEST_HOST=${LOG_DEST%%\:*}; # buildbot@master
                LOG_DEST_DIR=${LOG_DEST##*\:};  # /var/www/html/logs
                shift 2;;
        --log_url) LOG_URL=$2; shift 2;;
        --step_name) STEP_NAME=$2; shift 2;;
        --no_tests) DO_TESTS=1; shift 1;;
        --parallel) PARALLEL=$2; shift 2;;
        --on_demand) ON_DEMAND_BUILD=0; ONE_PASS_BUILD=0; shift 1;;
        --on_change) ON_CHANGE_BUILD=0; ONE_PASS_BUILD=0; shift 1;;
        *) [ "$*" != "" ] && echo "parsed options; arguments left are:$*:"
             break;;
    esac
done

WORK_PWD=`pwd`

# Ensure no residual failed-test error log from previous build 
rm -rf $WORK_PWD/$FAILED_TESTS_LOG

if [ "$STEP_NAME" = "unknown" ]; then
    print_error "FAILURE: ============================================================="
    print_error "FAILURE: Missing input argument '--step_name',  build step name must be specified."
    print_error "FAILURE: ============================================================="
    exit $BUILDBOT_FAILURE
fi

if [ ! -d $LSST_DEVEL ] ; then
    print_error "FAILURE: ============================================================="
    print_error "FAILURE: LSST_DEVEL: $LSST_DEVEL, was not passed as environment variable and thus does not exist."
    print_error "FAILURE: ============================================================="
    exit $BUILDBOT_FAILURE
fi

# Acquire Root PACKAGE Name; OnChange's version extracted from gitrepos addr
if [ "$1" = "" ]; then
    print_error "FAILURE: ============================================================="
    print_error "FAILURE: Missing input argument: '--package', package name must be supplied."
    print_error "FAILURE: ============================================================="
    exit $BUILDBOT_FAILURE
elif [ "$ON_CHANGE_BUILD" = "1" ]; then
    PACKAGE="$1"
else
    # need to convert input param from repository name to package name
    scm_url_to_package "$1"
    if [ "$SCM_PACKAGE" != "" ]; then
        PACKAGE="$SCM_PACKAGE"
        print "OnChange sets: PACKAGE:$PACKAGE:    STEP_NAME:  $STEP_NAME"
    else
        print_error "FAILURE: ============================================================="
        print_error "FAILURE: Change triggered builds require a valid url to the package repository as input."
        print_error "FAILURE: $1 is not formatted correctly."
        print_error "FAILURE: ============================================================="
        exit $BUILDBOT_FAILURE
    fi
fi

print "PACKAGE: $PACKAGE    STEP_NAME:  $STEP_NAME"

source $LSST_STACK"/loadLSST.sh"


#*************************************************************************
#First action...rebuild the $LSST_DEVEL cache
pretty_execute "eups admin clearCache -Z $LSST_DEVEL"
pretty_execute "eups admin buildCache -Z $LSST_DEVEL"

#*************************************************************************
step "Determine if $PACKAGE will be tested"

package_is_external $PACKAGE
if [ $? = 0 ]; then 
    print "External and pseudo packages are not tested, $PACKAGE is one of them."
    exit $BUILDBOT_SUCCESS
fi
package_is_special $PACKAGE
if [ $? = 0 ]; then
    print "WARNING: ============================================================="
    print "WARNING: Selected packages are not tested, $PACKAGE is one of them"
    print "WARNING: ============================================================="
    exit $BUILDBOT_WARNINGS
fi


# this gets $EXTERNAL_DEPS, $INTERNAL_DEPS, $RET_REVISION, $REVISION 
# and $SCM_LOCAL_DIR set for $PACKAGE

queryPackageInfo $PACKAGE

if [ -f $WORK_PWD/git/$PACKAGE/$REVISION/BUILD_OK ]; then
    print "PACKAGE: $PACKAGE $REVISION has BUILD_OK flag and will not be rebuilt."
    exit $BUILDBOT_SUCCESS
else
    print "PACKAGE: $PACKAGE $REVISION does not have BUILD_OK flag and will be rebuilt."
fi

PACKAGE_SCM_REVISION=$RET_REVISION
[[ "$DEBUG" ]] && print "PACKAGE: $PACKAGE PACKAGE_SCM_REVISION: $PACKAGE_SCM_REVISION"
echo "EUPS listing of setup packages prior to build:"
eups list -s

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
step "List build dependency tree for $PACKAGE"

if [ ! -e $EXTERNAL_DEPS ] || [ ! -e $INTERNAL_DEPS ]; then
    print_error "FAILURE: ============================================================="
    print_error "FAILURE: work/$EXTERNAL_DEPS or work/$INTERNAL_DEPS do not exist for: $CUR_PACKAGE  $REVISION."
    print_error "FAILURE: Possibly earlier buildstep 'extractDependencies' had an undetected failure."
    print_error "FAILURE: ============================================================="
    exit $BUILDBOT_FAILURE
fi
cat $EXTERNAL_DEPS
cat $INTERNAL_DEPS

while read CUR_PACKAGE CUR_VERSION; do
    cd $WORK_PWD
    step "Setup external dependencies for $CUR_PACKAGE"
    while read EX_CUR_PACKAGE EX_CUR_VERSION; do
        # 31 May 2012# pretty_execute "setup  $EX_CUR_PACKAGE $EX_CUR_VERSION"
        pretty_execute "setup -j $EX_CUR_PACKAGE $EX_CUR_VERSION"
        if [ $? != 0 ]; then
            FAIL_MSG="Failed in eups-set of $EX_CUR_PACKAGE @ $EX_CUR_VERSION during first pass at dependency installation."
        fi
    done < "$EXTERNAL_DEPS"

    echo "EUPS listing of setup packages after external dependencies setup:"
    eups list -s

    step "Checking $CUR_PACKAGE $CUR_VERSION status"
    # ---------------------------------------------------------------------
    # --  BLOCK1 -  this assumes that when NoTest is taken, that only a 
    # --            compilation is required and not a reload to check 
    # --            altered lib signatures or dependencies.
    # ---------------------------------------------------------------------

    if  [ -f "git/$CUR_PACKAGE/$CUR_VERSION/BUILD_OK" ] ; then
        [[ "$DEBUG" ]] && print "Local src directory is marked BUILD_OK"
        pretty_execute "setup -j -t current $CUR_PACKAGE"
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
            print_error "FAILURE: ============================================================="
            print_error "FAILURE: $CUR_PACKAGE failed to successfully build earlier in the one-pass ordering."
            print_error "FAILURE: ============================================================="
            exit $BUILDBOT_WARNINGS
        else 
            print_error "FAILURE: ============================================================="
            print_error "FAILURE: $CUR_PACKAGE is a dependent package of $STEP_NAME that was not marked as pre-built."
            print_error "FAILURE: Possibly '~/RHEL6/etc/LsstStackManifest.txt' is out of order, missing a dependency declaration, or $CUR_PACKAGE has cyclic dependencies."
            print_error "FAILURE: Better check which is the case."
            print_error "FAILURE: ============================================================="
            exit $BUILDBOT_FAILURE
        fi
    fi

    step "Building $CUR_PACKAGE $CUR_VERSION"

    # ----------------------------------------------------------------
    # -- Rest of build work is done within the package's source directory --
    # ----------------------------------------------------------------
    BUILD_ROOT=$PWD
    cd $WORK_PWD/git/$CUR_PACKAGE/$CUR_VERSION
    print $PWD

    # 31 May 2012# pretty_execute "setup -r . -k "
    pretty_execute "setup -r . -j "
    pretty_execute "eups list -s"
    saveSetupScript $BUILD_ROOT $CUR_PACKAGE $BUILD_NUMBER $PWD

    BUILD_STATUS=0
    unset BUILD_ERROR
    rm $BUILD_ROOT/$FAILED_TESTS_LOG

    # compile lib and build docs; then test executables; then install.
    scons_tests $CUR_PACKAGE
    pretty_execute "scons --verbose -j $PARALLEL opt=3 lib python doc"
    if [ $RETVAL != 0 ]; then
        BUILD_STATUS=2
        BUILD_ERROR="Failure of initial 'scons -j $PARALLEL opt=3 lib python doc' build ($BUILD_STATUS)."
        print_error $BUILD_ERROR
    elif [ $DO_TESTS = 0 -a "$SCONS_TESTS" = "tests" -a -d tests ]; then 
        # Built libs & doc OK, now test executables (examples and tests) 

	# Some tests depend on other binaries to be built, and there's a  race 
    # condition causing test failure if they're not built before test is run.
        if [ "$CUR_PACKAGE" = "ctrl_sched" -o "$CUR_PACKAGE" = "ctrl_events" ] ; then
            pretty_execute "scons --verbose opt=3 lib tests examples"
        else
            pretty_execute "scons --verbose -j $PARALLEL opt=3 lib tests examples"
        fi
        TESTING_RETVAL=$RETVAL
        FAILED_COUNT=`eval "find tests -name \"*.failed\" $SKIP_THESE_TESTS | wc -l"`
        if [ $FAILED_COUNT != 0 ]; then
            print_error "One or more required tests failed:"
            pretty_execute -anon 'find tests -name "*.failed"'
            # Developers want log of failed-tests entered in build-fail email
            for FAILED_FILE in `find tests -name "*.failed"`; do
                echo "================================================" &>>$BUILD_ROOT/$FAILED_TESTS_LOG
                echo "Failed unit test: $PWD/$FAILED_FILE" &>> $BUILD_ROOT/$FAILED_TESTS_LOG
                cat $FAILED_FILE&>> $BUILD_ROOT/$FAILED_TESTS_LOG
                echo "================================================" &>> $BUILD_ROOT/$FAILED_TESTS_LOG
            done
            # Developers want failed-test log entry to be highlighted in red
            cat $BUILD_ROOT/$FAILED_TESTS_LOG > /proc/self/fd/2
            BUILD_STATUS=4
            BUILD_ERROR="Failure of 'scons -j $PARALLEL opt=3 lib tests examples' build ($BUILD_STATUS)."
            print_error $BUILD_ERROR
        elif [ $TESTING_RETVAL != 0 ]; then
            # Probably failed in examples since the tests didn't report failure
            BUILD_STATUS=5
            BUILD_ERROR="Failure of 'scons -j $PARALLEL opt=3 lib tests examples' build ($BUILD_STATUS)."
            print_error $BUILD_ERROR
        else   # Built libs & doc OK, ran executables OK, now eups-install
            pretty_execute "scons --verbose version=$CUR_VERSION+$BUILD_NUMBER opt=3 lib install current declare"
            if [ $RETVAL != 0 ]; then
                BUILD_STATUS=3
                BUILD_ERROR="Failure of install: 'scons version=$CUR_VERSION+$BUILD_NUMBER opt=3 lib install current declare' build ($BUILD_STATUS)."
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
            pretty_execute "scons --verbose version=$CUR_VERSION+$BUILD_NUMBER opt=3 lib install current declare python"
            if [ $RETVAL != 0 ]; then
                BUILD_STATUS=1
                BUILD_ERROR="Failure of install: 'scons version=$CUR_VERSION+$BUILD_NUMBER opt=3 lib install current declare python' build ($BUILD_STATUS)."
                print_error $BUILD_ERROR
            else
                print "Success during Compile/Load/Install without-tests: $CUR_PACKAGE $CUR_VERSION"
                eups declare -t SCM $CUR_PACKAGE $CUR_VERSION+$BUILD_NUMBER
                if [ $? != 0 ]; then
                    print_error "WARNING: failure setting SCM tag on build product."
                fi
            fi
    fi

    print "BUILD_STATUS status after build/install: $BUILD_STATUS"
    # Archive log if explicitly requested on success and always on failure.
    if [ "$BUILD_STATUS" -ne "0" ]; then
        # preserve config log 
        LOG_FILE="config.log"
        if [ "$LOG_DEST" ]; then
            if [ -f "$LOG_FILE" ]; then
                copy_log $LOG_FILE $LOG_FILE $LOG_DEST_HOST $LOG_DEST_DIR $BUILDER_NAME'/build/'$BUILD_NUMBER'/steps/'$STEP_NAME'/logs' $LOG_URL
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
        print_error "FAILURE: ============================================================="
        print_error "FAILURE: Buildbot failed to build $PACKAGE due to an error building dependency: $CUR_PACKAGE."
        print_error "FAILURE: Dependency: $CUR_PACKAGE (version: $CUR_VERSION)"
        print_error "FAILURE: $BUILD_ERROR"
        print_error "FAILURE: ============================================================="
        emailFailure "$CUR_PACKAGE" "$SEND_TO" 
        clear_blame_data

        touch $WORK_PWD/git/$CUR_PACKAGE/$CUR_VERSION/BUILD_FAIL

        #   Following only necessary if failed during scons-install step
        if [ "`eups list -s $CUR_PACKAGE $CUR_VERSION 2> /dev/null | grep $CUR_VERSION | wc -l`" != "0" ]; then
            pretty_execute "setup -u -j $CUR_PACKAGE $CUR_VERSION"
        fi
        if [ "`eups list -c $CUR_PACKAGE $CUR_VERSION  &> /dev/null | grep $CUR_VERSION | wc -l`" != "0" ]; then
            pretty_execute "eups undeclare -c $CUR_PACKAGE $CUR_VERSION"
        fi
        print_error "Exiting since $CUR_PACKAGE failed to build/install successfully"

        if [ "$ONE_PASS_BUILD" = "1" ] ; then
            # Rate Failure if (FullBuild & Package=CurPackage)
            if [ "$PACKAGE" = "$CUR_PACKAGE" ] ; then
                exit $BUILDBOT_FAILURE
            else
                exit $BUILDBOT_WARNINGS
            fi
        elif [ "$ON_CHANGE_BUILD" = "0" ]; then
            # Rate Failure if (git-change & git-Package=CurPackage)
            if [ "$GIT_PACKAGE" = "$CUR_PACKAGE" ] ; then
                exit $BUILDBOT_FAILURE
            else
                exit $BUILDBOT_WARNINGS
            fi
        else # Not Full Build, not git-change build, ergo one-Pass_build
            exit $BUILDBOT_FAILURE
        fi
    fi

    # For full build, setup each successful install 
    setup -t current -j $CUR_PACKAGE
    if [ $? != 0 ]; then
        print_error "WARNING: unable to complete setup of installed $CUR_PACKAGE $CUR_VERSION. Continuing with package setup in local directory."
    fi
    print "eups list -s: after final dependent setup"
    eups list -s 
    print "-------------------------"
    eups list -t current -v $CUR_PACKAGE
    print "-------------------------"
    touch $WORK_PWD/git/$CUR_PACKAGE/$CUR_VERSION/BUILD_OK
    if [ $? == 0 ]; then
        rm -f $WORK_PWD/git/$CUR_PACKAGE/$CUR_VERSION/NEEDS_BUILD
        rm -f $WORK_PWD/git/$CUR_PACKAGE/$CUR_VERSION/BUILD_FAIL
    else
        print_error "WARNING: unable to set flag: $WORK_PWD/git/$CUR_PACKAGE/$CUR_VERSION/BUILD_OK; this source directory will be rebuilt on next use." 
    fi
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
exit $BUILDBOT_SUCCESS
