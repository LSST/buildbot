#! /bin/bash

#
# This script contains functions that are used in other  scripts, and
# is meant to be instantiated via:
#
# source ${0%/*}/gitBuildFunctions2.sh
#
# within those scripts.
# 
# TODO: Merge with gitBuildFunctions.sh 


getPackageName() {
    if [ "$1" == "" ]; then
        FAIL_MSG="No argument provided for getPackageName(). See LSST buildbot developer."
        emailFailure "NoArgument" "$BUCK_STOPS_HERE"
        exit 1
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
        FAIL_MSG="No package name provided for queryPackageInfo() check. See LSST buildbot developer."
        emailFailure "NoPackageNamed" "$BUCK_STOPS_HERE"
        exit 1
    fi

    arg=$1

   while read LINE; do
        package=`echo $LINE | awk '{print $1}'`
        version=`echo $LINE | awk '{print $2}'`
        if [ $package == $arg ]; then
            RET_PACKAGE=$package
            RET_REVISION=$version
            REVISION=$RET_REVISION
            SCM_LOCAL_DIR=$PWD/git/$1/$REVISION
            EXTERNAL_DEPS=$PWD/git/$1/$REVISION/external.deps
            INTERNAL_DEPS=$PWD/git/$1/$REVISION/internal.deps
            return
        fi
    done < manifest.list

    echo "RET_PACKAGE = $RET_PACKAGE"
    # note: reached after the return above, or by finishing the loop
    if [ $arg != $RET_PACKAGE ]; then
        FAIL_MSG="$arg not found. See LSST buildbot developer."
        emailFailure "Package Not Found" "$BUCK_STOPS_HERE"
        exit 1
    fi
}

#--------------------------------------------------------------------------
usage() {
#80 cols  ................................................................................
    echo "Usage: $0 [options] package"
    echo "Install a requested package from version control (trunk), and recursively"
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
    echo "             --production: setting up stack for production run"
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
# -- Some LSST internal packages should never be built from trunk --
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
    # 3 Jan 2012 removed '    -o $SPCL_PACKAGE = "base"  ' to force rebuild.
    if [ ${SPCL_PACKAGE:0:5} = "scons" \
        -o ${SPCL_PACKAGE} = "thirdparty_core"  \
        -o ${SPCL_PACKAGE} = "toolchain"  \
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
        -o ${SPCL_PACKAGE:0:5} = "mops_"  \
        -o ${SPCL_PACKAGE:0:4} = "lsst" ]; then 
        return 0
    else
        return 1
    fi
}

#--------------------------------------------------------------------------
# -- On Failure, email appropriate notice to proper recipient(s)
# $1 = package
# $2 = recipients  (May have embedded blanks)
# Pre-Setup: BLAME_TMPFILE : file log of last commit on $1
#            BLAME_EMAIL : email address of last developer to modify package
#            FAIL_MSG : text tuned to point of error
#            STEP_NAME : name of package being processed in this run.
#            URL_BUILDERS : web address to build log root directory
#            BUILDER_NAME : process input param indicating build type
#            BUCK_STOPS_HERE : email oddress of last resort
# return: 0  

emailFailure() {
    return
    local emailPackage=$1; shift
    local emailRecipients=$*;

    # send failure message to stderr for display 
    print_error $FAIL_MSG

    print "emailPackage = $emailPackage, STEP_NAME = $STEP_NAME"
    # only send email out if
    # 1) the package we're building is the same as the one that reported
    #    the error
    # OR
    # 2) we're doing an "on_demand_build"
    if [ "$emailPackage" != "$STEP_NAME" ]; then
        if [ "$STEP_NAME" != "on_demand_build" ]; then
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

====
Instructions
====

bash:

$ source $LSST_STACK/loadLSST.sh\n\
$ EUPS_PATH=$LSST_DEVEL:$LSST_STACK\n\
$ cd $RET_FAILED_PACKAGE_DIRECTORY\n\
$ setup -t $RET_SETUP_SCRIPT_NAME -r .\n\

[t]csh:

%% source $LSST_STACK/loadLSST.csh\n\
%% set EUPS_PATH $LSST_DEVEL:$LSST_STACK\n\
%% cd $RET_FAILED_PACKAGE_DIRECTORY\n\
%% setup -t $RET_SETUP_SCRIPT_NAME -r .\n\

Go to your local copy of $emailPackage, run the command:

setup -r . -k

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
###_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_
## Uncomment the next command  when ready to send to developers
###_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_
#    #cat email_body.txt | mail -c "$BUCK_STOPS_HERE" -s "$EMAIL_SUBJECT" "$EMAIL_RECIPIENT"
}

###_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_
#                 Might want to reuse following to avoid duplicate emails
###_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_
#emailFailure() {
#    if [ "$3" = "FETCH_BLAME" ]; then
#        # Determine last developer to modify the package
#        local LAST_MODIFIER=`svn info $SCM_LOCAL_DIR | grep 'Last Changed Author: ' | sed -e "s/Last Changed Author: //"`
#    
#        # Is LAST_MODIFIER already in the list of PACKAGE_OWNERS ?
#        local OVERLAP=`echo ${2}  | sed -e "s/.*${LAST_MODIFIER}.*/FOUND/"`
#        unset DEVELOPER
#        if [ "$OVERLAP" != "FOUND" ]; then
#            local url="$PACKAGE_OWNERS_URL?format=txt"
#            DEVELOPER=`curl -s $url | grep "sv ${LAST_MODIFIER}" | sed -e "s/sv ${LAST_MODIFIER}://" -e "s/ from /@/g"`
#            if [ ! "$DEVELOPER" ]; then
#                DEVELOPER=$BUCK_STOPS_HERE
#                print "*** Error: did not find last modifying developer of ${LAST_MODIFIER} in $url"
#                print "*** Expected \"sv <user>: <name> from <somewhere.dom>\""
#            fi
#    
#            print "$BUCK_STOPS_HERE will send build failure notification to $2 and $DEVELOPER"
#            MAIL_TO="$2, $DEVELOPER"
#        else
#            print "$BUCK_STOPS_HERE will send build failure notification to $2"
#        fi
#    fi
###_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_#_
#--------------------------------------------------------------------------
