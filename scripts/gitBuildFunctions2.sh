#! /bin/bash

#
# This script contains functions that are used in other  scripts, and
# is meant to be instantiated via:
#
# source ${0%/*}/gitBuildFunctions2.sh
#
# within those scripts.
# 

#--
# Library Functions
# -----------------
# getPackageName()
# queryPackageInfo()
# usage()
# package_is_special()
# emailFailure()
# -- 


getPackageName() {
    if [ "$1" == "" ]; then
        print_error "============================================================="
        print_error "No argument provided for getPackageName(). See LSST buildbot developer."
        print_error "============================================================="
        exit $BUILDBOT_FAILURE
    fi

    value=0
    while read LINE; do
        _package=`echo $LINE | awk '{print $1}'`
        _version=`echo $LINE | awk '{print $2}'`
        if [ "$value" == "$1" ] ; then
            PACKAGE=$_package
            return
        fi
        value=`expr $value + 1`
    done < master.deps
    PACKAGE="build complete"
}

queryPackageInfo() {
    if [ "$1" = "" ]; then
        print_error "============================================================="
        print_error "Error in queryPackageInfo(): No package name provided. See LSST buildbot developer."
        print_error "============================================================="
        exit $BUILDBOT_FAILURE
    fi
    arg=$1

    local_revision=`grep -w $arg manifest.list | awk '{ print $2 }'`
    if [ "local_revision" != "" ]; then
        RET_PACKAGE=$arg
        RET_REVISION=$local_revision
        REVISION=$RET_REVISION
        SCM_LOCAL_DIR=$PWD/git/$1/$REVISION
        EXTERNAL_DEPS=$PWD/git/$1/$REVISION/external.deps
        INTERNAL_DEPS=$PWD/git/$1/$REVISION/internal.deps
        return
    fi

    print_error "============================================================="
    print_error "Error in queryPackageInfo(): named package: $arg, not found in 'manifest.list'. See LSST buildbot developer."
    print_error "============================================================="
    exit $BUILDBOT_FAILURE
}

#--------------------------------------------------------------------------
usage() {
#80 cols  ................................................................................
    echo "Usage: $0 [options] package"
    echo "Install a requested package from version control, and recursively"
    echo "ensure that its dependencies are also installed from version control."
    echo
    echo "Options (must be in this order):"
    echo "                --verbose: print out extra debugging info"
    echo "                  --force: if package already installed, re-install "
    echo "       --dont_log_success: if specified, only save logs if install fails"
    echo "        --log_dest <dest>: scp destination for config.log,"
    echo "                          eg \"buildbot@master:/var/www/html/logs\""
    echo "          --log_url <url>: URL prefix for the log destination,"
    echo "                          eg \"http://master/logs/\""
    echo "  --build_number <number>: buildbot's build number assigned to run"
    echo "    --slave_devel <path> : LSST_DEVEL=<path>"
    echo "               --no_tests: only build package, don't run tests"
    echo "       --parallel <count>: if set, parallel builds set to <count>"
    echo "                          else, parallel builds count set to 2."
    echo " where $PWD is location of slave's work directory"
}
#--------------------------------------------------------------------------

#--------------------------------------------------------------------------
# ---------------
# -- Functions --
# ---------------

#--------------------------------------------------------------------------
# -- On Failure, email appropriate notice to proper recipient(s)
# $1 = package
# $2 = recipients  (May have embedded blanks)
# Pre-Setup: STEP_FAILURE_BLAME : file log of last commit on $1
#            BLAME_EMAIL : email address of last developer to modify package
#            FAIL_MSG : text tuned to point of error
#            ONE_PASS_BUILD : indicates if doing on_change or on_demand builds
#            STEP_NAME : name of package being processed in this run.
#            URL_BUILDERS : web address to build log root directory
#            BUILDER_NAME : process input param indicating build type
#            BUCK_STOPS_HERE : email oddress of last resort
#            RET_FAILED_PACKAGE_DIRECTORY: package directory which failed build
#                                          if compile/build/test failure
# return: 0  

emailFailure() {
    local emailPackage=$1; shift
    local emailRecipients=$*;

    print "emailPackage: $emailPackage, STEP_NAME: $STEP_NAME SCM_PACKAGE: $SCM_PACKAGE ON_CHANGE_BUILD: $ON_CHANGE_BUILD"
    local localPackage="$PACKAGE"
    if [ "$ON_CHANGE_BUILD" = "0" ] ; then
        localPackage="$SCM_PACKAGE"
    fi
    # only send email out if
    # 1) package being built is same as one reporting error; OR
    # 2) doing a ONE_PASS_BUILD and not a full build
    if [ "$emailPackage" != "$localPackage" ]; then
        if [ "$ONE_PASS_BUILD" = "1" ]  ; then
            print "Not ONE_PASS_BUILD: Not sending e-mail until $emailPackage build";
            return 0
        fi
    fi
    
    #/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
    # raa 11 Mar 2012        F O R     D E B U G
    if [ "$ON_CHANGE_BUILD" = "0" ]; then
        MAIL_TO="$BUCK_STOPS_HERE"
    else
        MAIL_TO="$emailRecipients"
    fi
    # raa 11 Mar 2012        F O R     D E B U G
    #/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/


    URL_MASTER_BUILD="$URL_BUILDERS/$BUILDER_NAME/builds"
    EMAIL_SUBJECT="LSST automated build failure: package: $emailPackage in $BUILDER_NAME"

    [[ "$DEBUG" ]] && print "TO: $MAIL_TO; Subject: $EMAIL_SUBJECT"

    rm -f email_body.txt
    printf "\
from: \"Buildbot\" <$BUCK_STOPS_HERE>\n\
subject: $EMAIL_SUBJECT\n\
to: \"Godzilla\" <robyn@noao.edu>\n \
cc: \"Buildbot\" <$BUCK_STOPS_HERE>\n\n" \
>> email_body.txt
# REPLACE 'TO:' ABOVE " to: $MAIL_TO\n"               & add trailing slash
#to: $MAIL_TO\n
# Also  add           " cc: $BUCK_STOPS_HERE\n\n "    & add trailing slash

    # Following is if error is failure in Compilation/Test/Build
    if  [ "$BLAME_EMAIL" != "" ] ; then
        FAILED_PACKAGE_VERSION=`basename $RET_FAILED_PACKAGE_DIRECTORY`
        printf "\n\
$FAIL_MSG\n\
You were notified because you are either the package's owner or its last modifier.\n\n" \
>> email_body.txt
printf "\n\
================================================\n\
To reconstruct this environment do the following:\n\
================================================\n\
Please refer to the following page, for an explanation of the following
and what to do in case of a problem:
    http://dev.lsstcorp.org/trac/wiki/Buildbot

=============
Instructions
=============
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
        cat $STEP_FAILURE_BLAME \
>> email_body.txt
        if [ -e $BUILD_ROOT/$FAILED_TESTS_LOG ] && [ -f $BUILD_ROOT/$FAILED_TESTS_LOG ] ; then
            echo "\nFailed tests:\n"\
            cat $BUILD_ROOT/$FAILED_TESTS_LOG \
>> email_body.txt
        fi
    else  # For Non-Compilation/Test/Build failures directed to BUCK_STOPS_HERE
        printf "\
A build/installation of package \"$emailPackage\" failed\n\n\
You were notified because you are Buildbot's nanny.\n\n\
$FAIL_MSG\n\n\
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
