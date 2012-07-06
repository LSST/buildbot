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
    echo "                --verbose: print out extra debugging info"
    echo "                  --force: if package already installed, re-install "
    echo "       --dont_log_success: if specified, only save logs if install fails"
    echo "        --log_dest <dest>: scp destination for config.log,"
    echo "                          eg \"buildbot@master:/var/www/html/logs\""
    echo "          --log_url <url>: URL prefix for the log destination,"
    echo "                          eg \"http://master/logs/\""
    echo "  --build_number <number>: buildbot's build number assigned to run"
    echo "    --slave_devel <path> : LSST_DEVEL=<path>"
    echo "             --production: setting up stack for production run"
    echo "               --no_tests: only build package, don't run tests"
    echo "       --parallel <count>: if set, parallel builds set to <count>"
    echo "                          else, parallel builds count set to 2."
    echo " where $PWD is location of slave's work directory"
}
#--------------------------------------------------------------------------

DEBUG=debug

source ${0%/*}/gitConstants.sh
source ${0%/*}/build_functions.sh
source ${0%/*}/gitBuildFunctions.sh

PROCESS=${0%/*}

#--------------------------------------------------------------------------
# ---------------
# -- Functions --
# ---------------
#--------------------------------------------------------------------------
# -- Some LSST internal packages should never be built from master --
# $1 = eups package name
# return 0 if a special LSST package which should be considered external
# return 1 if package should be processed as usual
package_is_special() {
    if [ "$1" = "" ]; then
        FAIL_MSG="No package name provided for package_is_special check. See LSST buildbot developer."
        emailFailure "NoPackageNamed" "$BUCK_STOPS_HERE"
        exit 1
    fi
    local SPCL_PACKAGE="$1"

    # 23 Nov 2011 installed toolchain since it's not in active.list, 
    #             required by tcltk but not an lsstpkg distrib package.
    # 27 Jan 2012  added obs_cfht (bit rot)
    # 13 Feb 2012 added *_pipeline (old)
    # 14 Feb 2012 added ip_diffim (too new)
        #-o ${SPCL_PACKAGE} = "ip_diffim"  \
    # 16 Feb 2012 added meas_extensions_*(too new) and meas_multifit (old)
    if [ ${SPCL_PACKAGE}         = "coadd_pipeline"  \
        -o ${SPCL_PACKAGE}       = "ip_pipeline"  \
        -o ${SPCL_PACKAGE}       = "meas_multifit"  \
        -o ${SPCL_PACKAGE}       = "meas_pipeline"  \
        -o ${SPCL_PACKAGE:0:5}   = "mops_"  \
        -o ${SPCL_PACKAGE}       = "obs_cfht"  \
        -o ${SPCL_PACKAGE}       = "obs_subaru"  \
        -o ${SPCL_PACKAGE}       = "auton"  \
        -o ${SPCL_PACKAGE:0:6}   = "condor"  \
        -o ${SPCL_PACKAGE:0:7}   = "devenv_"  \
        -o ${SPCL_PACKAGE}       = "gcc"  \
        -o ${SPCL_PACKAGE}       = "mpfr"  \
        -o ${SPCL_PACKAGE}       = "sconsUtils" \
        -o ${SPCL_PACKAGE}       = "ssd"  \
        -o ${SPCL_PACKAGE}       = "toolchain" \
        -o ${SPCL_PACKAGE}       = "afwdata" \
        -o ${SPCL_PACKAGE}       = "astrometry_net_data" \
        -o ${SPCL_PACKAGE}       = "coadd_pipeline_data"  \
        -o ${SPCL_PACKAGE}       = "isrdata"  \
        -o ${SPCL_PACKAGE}       = "meas_algorithmdata"  \
        -o ${SPCL_PACKAGE}       = "multifit"  \
        -o ${SPCL_PACKAGE}       = "simdata"  \
        -o ${SPCL_PACKAGE}       = "subaru"  \
        -o ${SPCL_PACKAGE}       = "testdata_subaru"  \
        ]; then
        return 0
    fi
    return 1
}

#--------------------------------------------------------------------------
# -- On Failure, email appropriate notice to proper recipient(s)
# $1 = package
# $2 = recipients  (May have embedded blanks)
# Pre-Setup: BLAME_TMPFILE : file log of last commit on $1
#            BLAME_EMAIL : email address of last developer to modify package
#            PROCESS : name of running process
#            FAIL_MSG : text tuned to point of error
#            STEP_NAME : name of package being processed in this run.
#            URL_BUILDERS : web address to build log root directory
#            BUILDER_NAME : process input param indicating build type
#            BUCK_STOPS_HERE : email oddress of last resort
#            RET_FAILED_PACKAGE_DIRECTORY: package directory which failed build
#                                      if compilation/build/test failure
# return: 0  

emailFailure() {
    local emailPackage=$1; shift
    local emailRecipients=$*;

    # send failure message to stderr for display 
    PROCESS_FAIL_MSG="$PROCESS: $FAIL_MSG"
    print_error $PROCESS_FAIL_MSG

    print "emailPackage = $emailPackage, STEP_NAME = $STEP_NAME"
    # only send email out if
    # 1) the package we're building is the same as the one that reported
    #    the error
    # OR
    # 2) we're doing an "on_demand_build" or "prepare_packages" build
    if [ "$emailPackage" != "$STEP_NAME" ]; then
        if [ "$STEP_NAME" != "on_demand_build"  -a  "$STEP_NAME" != "prepare_packages" ]; then
            print "Not sending e-mail;  waiting to report until actual package build";
            return 0
        fi
    fi
    MAIL_TO="$emailRecipients"
    URL_MASTER_BUILD="$URL_BUILDERS/$BUILDER_NAME/builds"
    EMAIL_SUBJECT="LSST automated build failure: package $emailPackage in $BUILDER_NAME"

    [[ "$DEBUG" ]] && print "TO: $MAIL_TO; Subject: $EMAIL_SUBJECT; $BUILDER_NAME"

    rm -f email_body.txt
    printf "\
from: \"Buildbot\" <$BUCK_STOPS_HERE>\n\
subject: $EMAIL_SUBJECT\n\
to: \"Godzilla\" <robyn@noao.edu>\n\
cc: \"Mothra\" <$BUCK_STOPS_HERE>\n" \
>> email_body.txt
#to: \"Godzilla\" <robyn@lsst.org>\n" \
# REPLACE 'TO:' ABOVE " to: $MAIL_TO\n"               & add trailing slash
# Also  add           " cc: $BUCK_STOPS_HERE\n\n "    & add trailing slash

    # Following is if error is failure in Compilation/Test/Build
    if  [ "$BLAME_EMAIL" != "" ] ; then
        FAILED_PACKAGE_VERSION=`basename $RET_FAILED_PACKAGE_DIRECTORY`
        printf "\n\
$PROCESS_FAIL_MSG\n\
You were notified because you are either the package's owner or its last modifier.\n\n" \
>> email_body.txt
printf "\n\
================================================\n\
To reconstruct this environment do the following:\n\
================================================\n\
Please refer to the following page, for an explanation of the following
and what to do in case of a problem:

http://dev.lsstcorp.org/trac/wiki/Buildbot

====
Instructions
====

Go to your local copy of $emailPackage and run the commands:

%% EUPS_PATH=$LSST_DEVEL:$LSST_STACK\n\
%% setenv EUPS_PATH $EUPS_PATH   # [t]csh users only! \n\
%% setup --nolocks -t $RET_SETUP_SCRIPT_NAME -r .\n\

and debug there.
\n"\
>> email_body.txt
printf "\n\
=====================\n\
Details of the error:
=====================\n\
The failure log is available at: ${URL_MASTER_BUILD}/${BUILD_NUMBER}/steps/$STEP_NAME/logs/stdio\n\
The Continuous Integration build log is available at: ${URL_MASTER_BUILD}/${BUILD_NUMBER}\n\n\
Commit log:\n" \
>> email_body.txt
        cat $BLAME_TMPFILE \
>> email_body.txt
    else  # For Non-Compilation/Test/Build failures directed to BUCK_STOPS_HERE
        printf "\
A build/installation of package \"$emailPackage\" failed\n\n\
You were notified because you are Buildbot's nanny.\n\n\
$PROCESS_FAIL_MSG\n\n\
The failure log is available at: ${URL_MASTER_BUILD}/${BUILD_NUMBER}/steps/$STEP_NAME/logs/stdio\n"\
>> email_body.txt
    fi

    printf "\
\n--------------------------------------------------\n\
Sent by LSST buildbot running on `hostname -f`\n\
Questions?  Contact $BUCK_STOPS_HERE \n" \
>> email_body.txt

    /usr/sbin/sendmail -t < email_body.txt
    rm email_body.txt
}

#--------------------------------------------------------------------------

# -------------------
# -- get arguments --
# -------------------

options=$(getopt -l verbose,boot,force,dont_log_success,log_dest:,log_url:,builder_name:,build_number:,slave_devel:,production,no_tests,parallel:,package:,step_name: -- "$@")

LOG_SUCCESS=0
BUILDER_NAME=""
BUILD_NUMBER=0
STEP_NAME="unknown"
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
        --package) PACKAGE=$2; shift 2;;
        --step_name) STEP_NAME=$2; shift 2;;
        *) echo "parsed options; arguments left are: $*"
             break;;
    esac
done

echo "STEP_NAME = $STEP_NAME"
if [ "$STEP_NAME" = "unknown" ]; then
    FAIL_MSG="Missing argument --step_name must be specified"
    emailFailure "Unknown"  "$BUCK_STOPS_HERE"
    exit 1
fi


if [ ! -d $LSST_DEVEL ] ; then
    FAIL_MSG="LSST_DEVEL: $LSST_DEVEL does not exist."
    emailFailure "Unknown" "$BUCK_STOPS_HERE"
    exit 1
fi

PACKAGE=$1
if [ "$PACKAGE" = "" ]; then
    FAIL_MSG="No package name was provided as an input parameter."
    emailFailure "Unknown" "$BUCK_STOPS_HERE"
    exit 1
fi

print "PACKAGE: $PACKAGE"

WORK_PWD=`pwd`

#Allow developers to access slave directory
umask 002

source $LSST_STACK"/loadLSST.sh"

#*************************************************************************
step "Determine if $PACKAGE will be tested"

package_is_special $PACKAGE
if [ $? = 0 ]; then
    print "Selected packages are not tested via master-vs-master, $PACKAGE is one of them"
    exit 0
fi
package_is_external $PACKAGE
if [ $? = 0 ]; then 
    print "External packages are not tested via master-vs-master"
    exit 0
fi


prepareSCMDirectory $PACKAGE "BOOTSTRAP"
if [ $RETVAL != 0 ]; then
    FAIL_MSG="Failed to extract $PACKAGE source directory during setup for bootstrap dependency."
    emailFailure "$PACKAGE" "$BUCK_STOPS_HERE"
    exit 1
fi
