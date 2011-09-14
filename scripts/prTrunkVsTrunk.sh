#! /bin/bash
# install a requested package from version control, and recursively
# ensure that its minimal dependencies are installed likewise


#--------------------------------------------------------------------------
usage() {
#80 cols  ................................................................................
    echo "Usage: $0 [options] package"
    echo "Install a requested package from version control (trunk), and recursively"
    echo "ensure that its dependencies are also installed from version control."
    echo
    echo "Options (must be in this order):"
    echo "                -verbose: print out extra debugging info"
    echo "                  -force: if package already installed, re-install "
    echo "       -dont_log_success: if specified, only save logs if install fails"
    echo "        -log_dest <dest>: scp destination for config.log,"
    echo "                          eg \"buildbot@master:/var/www/html/logs\""
    echo "          -log_url <url>: URL prefix for the log destination,"
    echo "                          eg \"http://master/logs/\""
    echo "    -builddir <instance>: identifies slave instance at \"slave/<name>\""
    echo "  -build_number <number>: buildbot's build number assigned to run"
    echo "           -slave_devel : if set, LSST_DEVEL= $PWD/buildbotSandbox"
    echo "                          else, LSST_DEVEL=$HOME/buildbotSandbox"
    echo "             -production: setting up stack for production run"
    echo "               -no_tests: only build package, don't run tests"
    echo " where $PWD is location of slave's work directory"
}
#--------------------------------------------------------------------------

DEBUG=debug
DEV_SERVER="lsstdev.ncsa.uiuc.edu"
SVN_SERVER="svn.lsstcorp.org"
WEB_ROOT="/var/www/html/doxygen"

source ${0%/*}/prBuildFunctions.sh

#Exclude known persistent test failures until they are fixed or removed
#   Code Developer should install into tests/SConscript:
#       ignoreList=["testSdqaRatingFormatter.py"]
#       tests = lsst.tests.Control(env, ignoreList=ignoreList, verbose=True)
# If not use e.g.    SKIP_THESE_TESTS="| grep -v testSdqaRatingFormatter.py "
SKIP_THESE_TESTS=""


#--------------------------------------------------------------------------
# ---------------
# -- Functions --
# ---------------
#--------------------------------------------------------------------------
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


#--------------------------------------------------------------------------
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
        -o $SPCL_PACKAGE = "meas_multifitData"  \
        -o $SPCL_PACKAGE = "auton"  \
        -o $SPCL_PACKAGE = "ssd"  \
        -o $SPCL_PACKAGE = "mpfr"  \
        -o ${SPCL_PACKAGE:0:6} = "condor"  \
        -o $SPCL_PACKAGE = "ip_diffim"  \
        -o $SPCL_PACKAGE = "base"  \
        -o ${SPCL_PACKAGE:0:4} = "lsst" ]; then 
        return 0
    else
        return 1
    fi
}

#--------------------------------------------------------------------------
# -- On Failure, email appropriate notice to proper recipient(s)
# $1 = package
# $2 = recipients
# $3 = "FIND_DEVELOPER" then scan for last modifier of package
# return: 0  

emailFailure() {
    TRUNK_VS_TRUNK=$BUILDER_NAME
    URL_TRUNK_VS_TRUNK="http://dev.lsstcorp.org/build/builders/$BUILDER_NAME/builds"
    MAIL_TO="$2"
    if [ "$3" = "FIND_DEVELOPER" ]; then
        # Determine last developer to modify the package
        local LAST_MODIFIER=`svn info $SVN_LOCAL_DIR | grep 'Last Changed Author: ' | sed -e "s/Last Changed Author: //"`
    
        # Is LAST_MODIFIER already in the list of PACKAGE_OWNERS (aka $2)?
        local OVERLAP=`echo ${2}  | sed -e "s/.*${LAST_MODIFIER}.*/FOUND/"`
        unset DEVELOPER
        if [ "$OVERLAP" != "FOUND" ]; then
            local url="$PACKAGE_OWNERS_URL?format=txt"
            DEVELOPER=`curl -s $url | grep "sv ${LAST_MODIFIER}" | sed -e "s/sv ${LAST_MODIFIER}://" -e "s/ from /@/g"`
            if [ ! "$DEVELOPER" ]; then
                DEVELOPER=$BUCK_STOPS_HERE
                print "*** Error: did not find last modifying developer of ${LAST_MODIFIER} in $url"
                print "*** Expected \"sv <user>: <name> from <somewhere.dom>\""
            fi
    
            print "$BUCK_STOPS_HERE will send build failure notification to $2 and $DEVELOPER"
            MAIL_TO="$2, $DEVELOPER"
        else
            print "$BUCK_STOPS_HERE will send build failure notification to $2"
        fi
    fi

    EMAIL_SUBJECT="LSST automated build failure: $1 trunk in $TRUNK_VS_TRUNK"

    rm -f email_body.txt
##_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_
# Replace following in next command when debugged AND fix up print statements in above block
#to: $MAIL_TO\n\
##_#_#_#_#_#_#_#_#_#_#_##_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_
    printf "\
from: \"Buildbot\" <$BUCK_STOPS_HERE>\n\
subject: $EMAIL_SUBJECT\n\
to: \"Roberta Allsman\" <rallsman@lsst.org>\n\
cc: $BUCK_STOPS_HERE\n\n" >> email_body.txt
    printf "\
A build of the trunk version of \"$1\" failed, against trunk versions of its dependencies.\n\n\
You were notified because you are either the package's owner or its last modifier.\n\n\
The $PACKAGE failure log is available at: ${URL_TRUNK_VS_TRUNK}/${BUILD_NUMBER}/steps/$PACKAGE/logs/stdio\n\
The Continuous Integration build log is available at: ${URL_TRUNK_VS_TRUNK}/${BUILD_NUMBER}\n" >> email_body.txt
    printf "\
Until next Monday, the build directories will be available for copy from: fbot.ncsa.illinois.edu:$WORK_PWD/svn/\n\n\
svn info:\n" >> email_body.txt
    svn_info $SVN_LOCAL_DIR ">> email_body.txt"
    printf "\
\n--------------------------------------------------\n\
Sent by LSST buildbot running on `hostname -f`\n\
Questions?  Contact $BUCK_STOPS_HERE \n" >> email_body.txt

    /usr/sbin/sendmail -t < email_body.txt
##_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_
# Uncomment the next command  when ready to send to developers
##_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_
    #cat email_body.txt | mail -c "$BUCK_STOPS_HERE" -s "$EMAIL_SUBJECT" "$EMAIL_RECIPIENT"
    rm email_body.txt
}
#--------------------------------------------------------------------------

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
    LOG_SUCCESS=1
    shift
else
    LOG_SUCCESS=0
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

BUILDER_NAME=""
if [ "$1" = "-builder_name" ]; then
    BUILDER_NAME=$2
    print "BUILDER_NAME: $BUILDER_NAME"
    shift 2
fi

BUILD_NUMBER=0
if [ "$1" = "-build_number" ]; then
    BUILD_NUMBER=$2
    shift 2
    print "BUILD_NUMBER: $BUILD_NUMBER"
fi

if [ "$1" = "-slave_devel" ]; then
    export LSST_DEVEL="$PWD/buildbotSandbox"
    shift 1
else
    export LSST_DEVEL="$HOME/buildbotSandbox"
fi
if [ ! -d $LSST_DEVEL ] ; then
    print "LSST_DEVEL: $LSST_DEVEL does not exist; contact the LSST buildbot guru."
    exit 1
fi

if [ "$1" = "-production" ]; then
    PRODUCTION_RUN=0
    shift 1
else
    PRODUCTION_RUN=1
fi

if [ "$1" = "-no_tests" ]; then
    DO_TESTS=1
    shift 1
else
    DO_TESTS=0
fi

PACKAGE=$1

print "PACKAGE: $PACKAGE"

WORK_PWD=`pwd`
rm -f $WORK_PWD/buildbot_FailedTests

#Allow developers to access slave directory
umask 002

source /lsst/DC3/stacks/default/loadLSST.sh

#*************************************************************************
#First action...clear the $LSST_DEVEL cache
pretty_execute "eups admin  -Z $LSST_DEVEL clearCache"
pretty_execute "eups admin  -Z $LSST_DEVEL buildCache"

#*************************************************************************
step "Determine if $PACKAGE will be tested"

package_is_special $PACKAGE
if [ $? = 0 ]; then
    print "Selected packages are not tested via trunk-vs-trunk, $PACKAGE is one of them"
    exit 0
fi
package_is_external $PACKAGE
if [ $? = 0 ]; then 
    print "External packages are not tested via trunk-vs-trunk"
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
# In order to get an accurate dependency table, ALL trunk svn directories
# must be extracted and 'setup -j <name>'  so that eups can deduce
# the dependencies from the source tree.  Only then should the build
# of the dependencies commence in the order specified.
#***********************************************************************

# -- setup root package in prep for dependency list generation
cd $SVN_LOCAL_DIR
pretty_execute "setup -r . -j"
pretty_execute "eups list $PACKAGE"
cd $WORK_PWD


#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
step " Bootstrap $PACKAGE Dependency Chain"

BOOT_DEPS="$WORK_PWD/buildbot_tVt_bootstrap"
cp /dev/null $BOOT_DEPS
if [ $? != 0 ]; then
   print "Unable to create temp file: $BOOT_DEPS for dependency sequencing."
   print "Test of $PACKAGE failed before it started."
   exit 1
fi
TEMP_FILE="$WORK_PWD/buildbot_tVt_temp"
cp /dev/null $TEMP_FILE
if [ $? != 0 ]; then
   print "Unable to create temp file $TEMP_FILE for dependency sequencing."
   print "Test of $PACKAGE failed before it started."
   exit 1
fi
python ${0%/*}/orderDependents.py -t $TEMP_FILE $PACKAGE > $BOOT_DEPS

COUNT=0
while read LINE; 
do
    print "   $COUNT  $LINE"
    (( COUNT++ ))
done < $BOOT_DEPS

step "Bootstrap $PACKAGE dependency tree"
while read CUR_PACKAGE CUR_VERSION CUR_DETRITUS; do
    cd $WORK_PWD
    #++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    # setup only the DM svn-able packages so correct dependency tree is created
    package_is_special $CUR_PACKAGE
    if [ $? = 0 ] ; then 
        continue; 
    fi
    package_is_external ${CUR_PACKAGE}
    if [ $? = 0 ]; then 
        continue; 
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
    cd $SVN_LOCAL_DIR
    pretty_execute "setup -r . -j"
    pretty_execute "eups list $CUR_PACKAGE"
    cd $WORK_PWD
    
# -- Loop around to next entry in bootstrap dependency list --
done < "$BOOT_DEPS"

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
step "Generate accurate dependency tree for $PACKAGE build"
REAL_DEPS="$WORK_PWD/buildbot_tVt_real"
cp /dev/null $REAL_DEPS
if [ $? != 0 ]; then
   print "Unable to create temporary file for dependency sequencing."
   print "Test of $PACKAGE failed before it started."
   exit 1
fi
TEMP_FILE="$WORK_PWD/buildbot_tVt_realtemp"
cp /dev/null $TEMP_FILE
if [ $? != 0 ]; then
   print "Unable to create temp file $TEMP_FILE for dependency sequencing."
   print "Test of $PACKAGE failed before it started."
   exit 1
fi
python ${0%/*}/orderDependents.py -s -t $TEMP_FILE $PACKAGE > $REAL_DEPS
#python ${0%/*}/orderDependents.py -s $PACKAGE > $REAL_DEPS

COUNT=0
while read LINE; 
do
    print "   $COUNT  $LINE"
    (( COUNT++ ))
done < $REAL_DEPS


while read CUR_PACKAGE CUR_VERSION CUR_DETRITUS; do
    cd $WORK_PWD
    #++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    step "Install dependency $CUR_PACKAGE"

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

    # -- Process external packages  via lsstpkg --
    package_is_external ${CUR_PACKAGE}
    if [ $? = 0 ]; then
        print "Installing external package: $CUR_PACKAGE $CUR_VERSION"
        if [ $CUR_VERSION != "Current" ]; then
            if [ `eups list $CUR_PACKAGE $CUR_VERSION | wc -l` = 0 ]; then
                INSTALL_CMD="lsstpkg install $CUR_PACKAGE $CUR_VERSION"
                pretty_execute $INSTALL_CMD
                if [ $RETVAL != 0 ]; then
                    print "Failed to install $CUR_PACKAGE $CUR_VERSION with lsstpkg."
                    emailFailure "$CUR_PACKAGE" "$BUCK_STOPS_HERE"
                    exit 1
                else
                    print "External dependency: $CUR_PACKAGE, successfully installed."
                fi
            fi
        else
            # if dependency just needs 'current', go with it
            if [ `eups list $CUR_PACKAGE | wc -l` = 0 ]; then
                print "Failed to setup external dependency: $CUR_PACKAGE."
                print "An 'lsstpkg install' version was not provided."
                emailFailure "$CUR_PACKAGE" "$BUCK_STOPS_HERE"
                exit 1
            fi
            CUR_VERSION=""
        fi
        pretty_execute "setup -j $CUR_PACKAGE $CUR_VERSION"
        if [ $RETVAL != 0 ]; then
            print "Failed to setup external dependency: $CUR_PACKAGE $CUR_VERSION."
            emailFailure "$CUR_PACKAGE" "$BUCK_STOPS_HERE"
            exit 1
        fi
        print "External dependency: $CUR_PACKAGE $CUR_VERSION, successfully installed."
        continue
    fi



    # -----------------------------------
    # -- Prepare SVN directory for build --
    # -----------------------------------
    adjustBadEupsName $CUR_PACKAGE
    CUR_PACKAGE=$ADJUSTED_NAME

    prepareSvnDir $CUR_PACKAGE
    if [ $RETVAL != 0 ]; then
        print "svn checkout failed; is $CUR_PACKAGE $REVISION a valid version?"
        emailFailure "$CUR_PACKAGE" "$BUCK_STOPS_HERE"
        exit 1
    fi

    # Determine if desired package instance is already current & setup  and
    # not the specific package being validated
    if [ `eups list $CUR_PACKAGE $REVISION | grep "Current Setup" | wc -l` = 1  -a "$PACKAGE" != "$CUR_PACKAGE" ]; then
        print "$CUR_PACKAGE $REVISION is already eups-current and -setup; skipping installation."
        continue
    fi

    # ----------------------------------------------------------------
    # -- Rest of work is done within the package's source directory --
    # ----------------------------------------------------------------
    cd $SVN_LOCAL_DIR 

    # -------------------------------
    # -- setup for a package build --
    # -------------------------------
    pretty_execute "setup -r . -k "
    pretty_execute "eups list -s"

    BUILD_STATUS=0

    # build libs; then build tests; then install.
    scons_tests $CUR_PACKAGE
    pretty_execute "scons -j 2 opt=3 python"
    if [ $RETVAL != 0 ]; then
        print "Failure of Build/Load: $CUR_PACKAGE $REVISION"
        BUILD_STATUS=2
    elif [ $DO_TESTS = 0 -a "$SCONS_TESTS" = "tests" -a -d tests ]; then 
        # Built libs OK, want Tests built and run
        pretty_execute "scons -j 2 opt=3 tests"
        FAILED_COUNT=`eval "find tests -name \"*.failed\" $SKIP_THESE_TESTS | wc -l"`
        if [ $FAILED_COUNT != 0 ]; then
            print "One or more required tests failed:"
            pretty_execute -anon 'find tests -name "*.failed"'
            # cat .failed files to stdout
            for FAILED_FILE in `find tests -name "*.failed"`; do
                echo "================================================" >> $WORK_PWD/buildbot_FailedTests
                echo "Failed unit test: $PWD/tests/$FAILED_FILE" >> $WORK_PWD/buildbot_FailedTests
                cat $FAILED_FILE >> $WORK_PWD/buildbot_FailedTests
                echo "================================================" >> $WORK_PWD/buildbot_FailedTests
                echo "================================================" 
                echo "Failed unit test: $PWD/tests/$FAILED_FILE" 
                cat $FAILED_FILE
                echo "================================================" 
            done
            print "Failure of 'tests' Build/Run for $CUR_PACKAGE $REVISION"
            BUILD_STATUS=4
        else   # Built libs OK, ran tests OK, now eups-install
            pretty_execute "scons opt=3 install current declare python"
            if [ $RETVAL != 0 ]; then
                print "Failure of install: $CUR_PACKAGE $REVISION"
                BUILD_STATUS=3
            fi
            print "Success of Compile/Load/Test/Install: $CUR_PACKAGE $REVISION"
        fi
    else  # Built libs OK, no tests wanted|available, now eups-install
            pretty_execute "scons opt=3 install current declare python"
            if [ $RETVAL != 0 ]; then
                print "Failure of install: $CUR_PACKAGE $REVISION"
                BUILD_STATUS=1
            fi
            print "Success during Compile/Load/Install with-tests: $CUR_PACKAGE $REVISION"
    fi

    print "BUILD_STATUS status after test failure search: $BUILD_STATUS"
    # Archive log if explicitly requested on success and always on failure.
    if [ "$BUILD_STATUS" -ne "0" ]; then
        # preserve config log 
        LOG_FILE="config.log"
        pretty_execute pwd
        if [ "$LOG_DEST" ]; then
            if [ -f "$LOG_FILE" ]; then
                copy_log ${CUR_PACKAGE}_$REVISION/$LOG_FILE $LOG_FILE $LOG_DEST_HOST $LOG_DEST_DIR ${CUR_PACKAGE}/$REVISION $LOG_URL
            else
                print "No $LOG_FILE present."
            fi
        else
            print "No archive destination provided for log file."
        fi
    fi

    # -- return to primary work directory  --
    # --               later, possibly 'rm' source directory --
    cd $WORK_PWD

    # Time to exit due to build failure of a dependency
    if [ "$BUILD_STATUS" -ne "0" -a "$BUILD_STATUS" -ne "4" ]; then
        # Get Email List for Package Owners (returned in $PACKAGE_OWNERS)
        fetch_package_owners $CUR_PACKAGE

        print "Installation of $CUR_PACKAGE $REVISION failed."
        print "Unable to build trunk-vs-trunk version of $PACKAGE due to failed build of dependency: $CUR_PACKAGE $REVISION ."
        if [ "$CUR_PACKAGE" == "$PACKAGE" ]; then
            emailFailure "$CUR_PACKAGE"  "$PACKAGE_OWNERS" "FIND_DEVELOPER"
        else
            emailFailure "$CUR_PACKAGE" "$BUCK_STOPS_HERE"
        fi
        #   Following only necessary if failed during scons-install step
        if [ "`eups list $CUR_PACKAGE $REVISION -s`" != "" ]; then
            pretty_execute "setup -u -j $CUR_PACKAGE $REVISION"
        fi
        if [ "`eups list $CUR_PACKAGE $REVISION -c`" != "" ]; then
            pretty_execute "eups undeclare -c $CUR_PACKAGE $REVISION"
        fi
        print "Exiting since $CUR_PACKAGE failed to build/install successfully"
        exit 1
    fi

    # For production build, setup each successful install 
    print "-------------------------"
    setup -j $CUR_PACKAGE
    eups list -v $CUR_PACKAGE
    print "-------------------------"

# -------------------------------------------------
# -- Loop around to next entry in dependency list --
# -------------------------------------------------
done < "$REAL_DEPS"

echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "Following is the Cumulative Report of FAILED Unit Tests"
if [ -f "$WORK_PWD/buildbot_FailedTests" ]; then
    cat $WORK_PWD/buildbot_FailedTests
fi
echo " "
echo "Preceding is the Cumulative Report of FAILED Unit Tests"
echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "Successfully compiled and installed trunk-vs-trunk version of $PACKAGE"
echo " "
echo "(Failed tests are reported but not fatal during Production Build.)"
echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"

#*************************************************************************
#Last action...refresh the $LSST_DEVEL cache
pretty_execute "eups admin  -Z $LSST_DEVEL clearCache"
pretty_execute "eups admin  -Z $LSST_DEVEL buildCache"
#*************************************************************************
exit 0
