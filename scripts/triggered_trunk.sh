#! /bin/bash
# check named packages for changes (on the trunk) and build any that
# have changed since the last time this script was run

usage() {
    echo "Usage: $0 [options] <package names>"
    echo "Options (must be in this order):"
    echo "          -verbose: print out extra debugging info"
    echo "  -against_current: build against current versions of dependencies"
    echo "                    instead of minimal versions"
    echo "     -email_notify: if specified, notify this address instead of the package"
    echo "                    owner, if this build fails"
    echo "  -log_dest <dest>: scp destination for config.log,"
    echo "                    for example \"buildbot@master:/var/www/html/logs\""
    echo "    -log_url <url>: URL prefix for the log destination,"
    echo "                    for example \"http://master/logs/\""
    echo "      -name <name>: The name of this builder (used in email notifications)."
}

source ${0%/*}/build_functions.sh

SVN_SERVER="svn.lsstcorp.org"
SUMMARY_SVN="summary_svn" # summary of svn activity
rm -f $SUMMARY_SVN

# get arguments
if [ "$1" = "-verbose" -o "$1" = "-debug" ]; then
    VERBOSE=true
    VERBOSE_ARGS=$1
    shift
fi
if [ "$1" = "-against_current" ]; then
    AGAINST_CURRENT=$1
    MINIMAL_OR_CURRENT="current"
    shift
else
    MINIMAL_OR_CURRENT="minimal"
fi

if [ "$1" = "-email_notify" ]; then
    EMAIL_NOTIFY=$2
    shift 2
fi

LOG_ARGS="$LOG_ARGS -dont_log_success" # don't save logs of successful builds, to avoid confusion
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
if [ "$1" = "-name" ]; then
    BUILDER_NAME=$2
    shift 2
else
    BUILDER_NAME="[unknown]"
fi

# any packages specified?
if [ "$1" = "" -o "$1" = "--help" -o "$1" = "-h" -o "$1" = "-help" ]; then
    usage
    exit 1
fi

tee_print() {
    echo $@ | tee -a $SUMMARY_SVN
}

# for each package listed, check for updates
mkdir -p svn
while [ $1 ]; do
    PACKAGE=$1
    shift
    unset SVN_HAS_NEW
    unset ATTEMPT
#    tee_print "=== ========================================================================"

    SVN_SERVER_DIR=${PACKAGE/_//} # replace _ with / to derive svn directory from package name
    SVN_LOCAL_DIR=svn/${PACKAGE}_trunk

    if [ -d $SVN_LOCAL_DIR ]; then
	# record revision that is currently checked out
	lookup_svn_revision $SVN_LOCAL_DIR
	OLD_REVISION=$RET_REVISION
	SVN_LINE_COUNT=`svn update $SVN_LOCAL_DIR | wc -l`
	if [ $SVN_LINE_COUNT != "1" ]; then
	    SVN_HAS_NEW=true
	fi
    else # initial checkout -- should be rare
	unset OLD_REVISION
	SVN_URL=svn+ssh://$SVN_SERVER/DMS/$SVN_SERVER_DIR/trunk
#	print "$SVN_LOCAL_DIR doesn't exist; checking out from $SVN_URL"
#	SVN_CMD="svn checkout $SVN_URL $SVN_LOCAL_DIR 2>&1 | tail -5"
	SVN_CMD="svn checkout $SVN_URL $SVN_LOCAL_DIR | tail -5"
	pretty_execute $SVN_CMD
	SVN_HAS_NEW=true
    fi

    # TODO: note previous revision number, and show all changes to
    # this package since then?

    FAIL_FILE=${PACKAGE}_failed

    if [ $SVN_HAS_NEW ]; then
	CHANGED="$CHANGED $PACKAGE" # concatenate
    else
	UNCHANGED="$UNCHANGED $PACKAGE" # concatenate
    fi

    if [ -f $FAIL_FILE -o "$SVN_HAS_NEW" ]; then
	tee_print "=== ========================================================================"
    fi

    if [ -f $FAIL_FILE ]; then
	PREV_FAIL="$PREV_FAIL $PACKAGE"
	tee_print "=== $PACKAGE failed previous build"
	ATTEMPT=true
    fi

    if [ "$SVN_HAS_NEW" ]; then
	tee_print "=== $PACKAGE has changed"
	ATTEMPT=true
    fi

    if [ "$ATTEMPT" ]; then
	if [ "$AGAINST_CURRENT" ]; then
	    tee_print "=== Building against CURRENT versions of dependencies (not minimal versions)."
	else
	    tee_print "=== Building against MINIMAL versions of dependencies (not current versions)."
	fi
	ATTEMPTED="$ATTEMPTED $PACKAGE" # concatenate
	tee_print "--- ------------------------------------------------------------------------"
	svn_info $SVN_LOCAL_DIR "| tee -a $SUMMARY_SVN"
	# svn_info $SVN_LOCAL_DIR ">>$SUMMARY_SVN"
	# svn_info $SVN_LOCAL_DIR
	if [ "$OLD_REVISION" ]; then
	    svn log -v -r $OLD_REVISION:HEAD $SVN_LOCAL_DIR | awk '{print "--- "$0}' | tee -a $SUMMARY_SVN
	fi
	${0%/*}/trunk_install.sh $VERBOSE_ARGS $AGAINST_CURRENT -indent 4 $LOG_ARGS $PACKAGE trunk
	if [ $? = 0 ]; then
	    SUCCESSES="$SUCCESSES $PACKAGE" # concatenate names of successful packages
	    rm -f $FAIL_FILE
	else
	    FAILED_OVERALL=true
	    FAILURES="$FAILURES $PACKAGE" # concatenate names of failed packages
	    if [ ! -f "$FAIL_FILE" ]; then # failed this time but didn't fail previously
		fetch_package_owners $PACKAGE
		if [ "$EMAIL_NOTIFY" ]; then
		    EMAIL_RECIPIENT=$EMAIL_NOTIFY
		else
		    EMAIL_RECIPIENT=$PACKAGE_OWNERS
		fi
		print "Sending build failure notification to $EMAIL_RECIPIENT"
		EMAIL_SUBJECT="LSST automated build failure: $PACKAGE trunk in $BUILDER_NAME"

		rm -f email_body.txt
		printf "\
from: \"Buildbot\" <bbaker@ncsa.illinois.edu>\n\
subject: $EMAIL_SUBJECT\n\
to: $EMAIL_RECIPIENT\n\
cc: \"Bill Baker\" <bbaker@ncsa.illinois.edu>\n\n" >> email_body.txt
		printf "\
A build of the trunk version of \"$PACKAGE\" failed, against $MINIMAL_OR_CURRENT\n\
versions of its dependencies.\n\n\
You are being notified because you are listed as a package owner at:\n\n\
    $PACKAGE_OWNERS_URL\n\n\
For more details on the failure, see http://dev.lsstcorp.org/build/waterfall.\n\
In the column \"$BUILDER_NAME\", look for links to stdio, $PACKAGE/config.log,\n\
and $PACKAGE/build.log.\n\n\
svn info:\n\n" >> email_body.txt
		svn_info $SVN_LOCAL_DIR ">> email_body.txt"
		printf "\
\n--------------------------------------------------\n\
Sent by LSST buildbot running on `hostname -f`\n
Questions?  Contact Bill Baker, bbb@illinois.edu\n" >> email_body.txt

		/usr/sbin/sendmail -t < email_body.txt
#		cat email_body.txt | mail -c "bbaker@ncsa.uiuc.edu" -s "$EMAIL_SUBJECT" "$EMAIL_RECIPIENT"
		rm email_body.txt
	    else
		print "Not sending failure notification for $PACKAGE because previous attempt also failed."
	    fi
	    touch $FAIL_FILE
	fi
	echo # blank line between packages
    else
#	tee_print "=== $PACKAGE has not changed"
	SKIPPED="$SKIPPED $PACKAGE" # concatenate names of ignored packages
	if [ -f $FAIL_FILE ]; then
	    # can only succeed if all previous failures are now working
	    FAILED_OVERALL=true
	fi
    fi

    if [ "$FAILURES"  ]; then  FAILURES_DESC=$FAILURES;  else  FAILURES_DESC=" [none]"; fi
    if [ "$PREV_FAIL" ]; then PREV_FAIL_DESC=$PREV_FAIL; else PREV_FAIL_DESC=" [none]"; fi
    if [ "$CHANGED"   ]; then   CHANGED_DESC=$CHANGED;   else   CHANGED_DESC=" [none]"; fi
    if [ "$UNCHANGED" ]; then UNCHANGED_DESC=$UNCHANGED; else UNCHANGED_DESC=" [none]"; fi
    if [ "$SUCCESSES" ]; then SUCCESSES_DESC=$SUCCESSES; else SUCCESSES_DESC=" [none]"; fi
    if [ "$SKIPPED"   ]; then   SKIPPED_DESC=$SKIPPED;   else   SKIPPED_DESC=" [none]"; fi
    if [ "$ATTEMPTED" ]; then ATTEMPTED_DESC=$ATTEMPTED; else ATTEMPTED_DESC=" [none]"; fi
done

SUMMARY_LOG=summary.log
rm -f $SUMMARY_LOG

echo "=== ========================================================================"
echo "Incremental trunk build complete: `date`"       | tee -a $SUMMARY_LOG
echo                                                  | tee -a $SUMMARY_LOG
echo "     Changed since last build: $CHANGED_DESC"   | tee -a $SUMMARY_LOG
echo "                    Unchanged: $UNCHANGED_DESC" | tee -a $SUMMARY_LOG
echo "            Failed previously: $PREV_FAIL_DESC" | tee -a $SUMMARY_LOG
echo                                                  | tee -a $SUMMARY_LOG
echo "                    Attempted: $ATTEMPTED_DESC" | tee -a $SUMMARY_LOG
echo "                   Successful: $SUCCESSES_DESC" | tee -a $SUMMARY_LOG
echo "                       Failed: $FAILURES_DESC"  | tee -a $SUMMARY_LOG
echo                                                  | tee -a $SUMMARY_LOG
#echo "                      Skipped: $SKIPPED_DESC"   | tee -a $SUMMARY_LOG
#echo                                                  | tee -a $SUMMARY_LOG

if [ "$LOG_ARGS" ]; then
    cat $SUMMARY_SVN                               >> $SUMMARY_LOG
    copy_log summary $SUMMARY_LOG $LOG_DEST_HOST $LOG_DEST_DIR triggered $LOG_URL
    rm -f $SUMMARY_LOG $SUMMARY_SVN
fi

if [ "$FAILED_OVERALL" ]; then exit 1; else exit 0; fi
