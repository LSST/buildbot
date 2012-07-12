#!/bin/bash

# This script checks Cluster on-disk datasets against their git repositories. 
# If the on-disk version is older than the git-repository, email is sent
# to the Cluster stack guru for updating.

source ${0%/*}/gitConstants.sh
source ${0%/*}/build_functions.sh

DS_NAME=""
DS_GIT_NAME=""
DS_PATH=""

options=$(getopt -l name:,gitname:,path: -- "$@")

while true
do
    case $1 in
        --name) DS_NAME=$2; shift 2;;
        --gitname) DS_GIT_NAME=$2; shift 2;;
        --path) DS_PATH=$2; shift 2;;

        *) [ "$*" != "" ] && echo "parsed options; arguments left are:$*:"
             break;;
    esac
done



##
# sanity check to be sure we got all the arguments
##
if [ "$DS_NAME" == "" ] || [ "$DS_GIT_NAME" == "" ]  || [ "$DS_PATH" == "" ]; then
    print_error "usage: $0 --name <name> --gitname <git repository> --path <root path>"
    exit $BUILDBOT_FAILURE
fi

source $LSST_HOME/loadLSST.sh

# Preferred command below had to be split to acquire potential git error exit
#gitMasterId=`git ls-remote $DS_GIT_NAME master | awk '{print $1}'`
git ls-remote $DS_GIT_NAME master > gitMasterIds
if [ $? != 0 ]; then
    print_error "============================================================="  
    print_error "Failed to access git URL: $DS_GIT_NAME"
    print_error "============================================================="  
    exit $BUILDBOT_FAILURE
fi

gitMasterId=`cat gitMasterIds | awk '{print $1}'`
rm gitMasterIds
echo "gitMasterId: $gitMasterId"

WORK_PWD=`pwd`
cd $DS_PATH
diskId=`git show | grep "^commit " | sed -e "s/commit //"`
echo "diskId: $diskId"

if [ $gitMasterId != $diskId ]; then
#   email sent by buildmaster mailNotifier on FAILURE or WARNINGS return
    print_error "============================================================="  
    print_error "NOTICE: $DS_PATH is out-of-date." 
    print_error "        Update from git repository: $DS_GIT_NAME." 
    print_error "============================================================="
    print_error ""  
    exit $BUILDBOT_FAILURE
fi
