#!/bin/bash

# This script reports on the locks set by the drpRun*.py code.
# If locks exit, the step returns WARNING

source ${0%/*}/gitConstants.sh
source ${0%/*}/build_functions.sh

TMP_LOCK_USE="./tmpLockUse"
TMP_EMAIL_BODY="./tmpEmailBody.txt"

if [ "$DRP_LOCK_PATH" == "" ] ; then
    print_error "=============================================================" 
    print_error "FAILURE: python  global: DRP_LOCK_PATH does not exist. See Buildbot Guru."
    print_error "=============================================================" 
    exit $BUILDBOT_FAILURE
fi
ls -l $DRP_LOCK_PATH 

#if [ ! -e $DRP_LOCK_PATH ]; then
#    print_error "=============================================================" 
#    print_error "FAILURE: 'drpRun*.py' lock file:  $DRP_LOCK_PATH does not exist."
#    print_error "FAILURE: Can not check status of locks."
#    print_error "=============================================================" 
#    exit $BUILDBOT_FAILURE
#fi


USED_LOCKS="`ls -l $DRP_LOCK_PATH | grep ' rh6' | wc -l`"
if [ "$USED_LOCKS" = "0" ]; then
    print_error "============================================================="
    print_error "INFO: no DrpRun locks in use."
    print_error "============================================================="
    exit $BUILDBOT_SUCCESS
elif [ "$USED_LOCKS" = "$MAX_DRP_LOCKS" ] ; then
    print_error "============================================================="
    print_error "WARNING: no free drpRun locks available."
    print_error "============================================================="
else 
    print_error "============================================================="
    print_error "INFO: $USED_LOCKS out of $MAX_DRP_LOCKS locks in use"
    ls -lt $DRP_LOCK_PATH | grep ' rh.-'
    print_error "============================================================="
fi

# find lock files not modified in 24 hours and complain about them
rm -f $TMP_LOCK_USE
find $DRP_LOCK_PATH -name "rh6-*" -type f -mmin +1440 -exec ls -l {} \; > $TMP_LOCK_USE
if [ -e $TMP_LOCK_USE ]  && [ "`cat $TMP_LOCK_USE | wc -l `" != "0" ]; then
    print_error "============================================================="
    print_error "WARNING: Following drpRun locks inactive for 24 hours."
    cat $TMP_LOCK_USE 
    print_error "============================================================="

    rm -f $TMP_EMAIL_BODY
    printf "\
from: Buildbot <$BUCK_STOPS_HERE>\n\
subject: drpRun locks inactive for 24 hours\n\
to: <$LSST_DEVEL_RUNS_EMAIL>\n\
cc: Buildbot <$BUCK_STOPS_HERE>\n\n" \
>> $TMP_EMAIL_BODY
    printf "\
The following drpRun lock(s) have been inactive for at least 24 hours:\n" \
>> $TMP_EMAIL_BODY
    cat $TMP_LOCK_USE  >> $TMP_EMAIL_BODY
    printf "\n\
If an idle lock is yours and the job has terminated, remove the lock using:\n\
    setup testing_endtoend\n\
    # LOCK_ID=  name of lockfile, e.g. rh6-2
    RUN_ID=\`grep \'^Run:\' /lsst3/weekly/datarel-runs/locks/\$LOCK_ID | awk \'{print \$2}\'\`\n\
    drpRun.py -k \$RUN_ID\n\
    ls -l $DRP_LOCK_PATH\n"\
>> $TMP_EMAIL_BODY
    /usr/sbin/sendmail -t < $TMP_EMAIL_BODY
    rm -f $TMP_LOCK_USE $TMP_EMAIL_BODY

    exit $BUILDBOT_WARNINGS
else
    exit $BUILDBOT_SUCCESS
fi
