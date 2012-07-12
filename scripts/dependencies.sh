#!/bin/sh

# This script determines the dependencies for each package in $MANIFEST.
# This is meant to be run from the builds/./work directory.
#
# As a side task, it also sets up a package (named dependencies) requiring 
# all packages in order to build a one pass dependency tree of all DM packages; 
# The overall dependency tree is saved into builds/./work/AllPkgBuildOrderManifest.

# arguments - all optional
# --debug : includes additional debug logging
# --builder_name : name of this buildbot build e.g. Trunk_vs_Trunk
# --build_number : number assigned to this particular build
# --branch : git-branch from which source was extracted
# <tags> :  blank separated tags list used to extract prefered package versions 



#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
#      TBD:  Better add some more error checking in the conditionals
#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/



source ${0%/*}/gitConstants.sh

# -------------------
# -- get arguments --
# -------------------
DEBUG=""
BUILDER_NAME=""
BUILD_NUMBER=""
BRANCH=""

MANIFEST="manifest.list"
SOURCE_MANIFEST_SETUP="./SOURCE_MANIFEST_SETUP"
DM_PKG_BUILD_ORDER_MANIFEST="DmPkgBuildOrderManifest"
ALL_PKG_BUILD_ORDER_MANIFEST="AllPkgBuildOrderManifest"

options=$(getopt -l debug,builder_name:,build_number:,branch: -- "$@")

while true
do
    case $1 in
        --debug) DEBUG=1; shift 1;;
        --builder_name) BUILDER_NAME=$2; shift 2;;
        --build_number) BUILD_NUMBER=$2; shift 2;;
        --branch) BRANCH=$2; shift 2;;
        *) [ "$*" != "" ] && echo "parsed options; arguments left are:$*:"
             break;;
    esac
done

# Residual arguments are assumed to be eups tags
TAGS=$*

source $LSST_HOME/loadLSST.sh
[[ "$DEBUG" ]] && which python
[[ "$DEBUG" ]] && echo $PYTHON_PATH

if [ ! -e $MANIFEST ] || [ "`cat $MANIFEST | wc -l`" = "0" ]; then
    echo "FATAL: Failed to find file: \"$MANIFEST\" in buildbot work directory."
    exit $BUILDBOT_FAILURE
fi

# create MANIFEST source file to setup each package
cat $MANIFEST | sed -e "s/^/setup -j /" > $SOURCE_MANIFEST_SETUP
source $SOURCE_MANIFEST_SETUP
setup -k -t beta -t stable datarel
setup -k -t beta -t stable testing_endtoend
setup -k -t beta -t stable testing_pipeQA

#setup -t S12a -t beta -t stable `grep -w testing_endtoend $MANIFEST | awk '{print $1,$2}'`
#setup -t S12a -t beta -t stable `grep -w testing_pipeQA $MANIFEST | awk '{print $1,$2}'`
#setup -t S12a -t beta -t stable `grep -w datarel $MANIFEST | awk '{print $1,$2}'`
echo "----------------------------------------"
eups list datarel -s
eups list testing_endtoend -s
eups list testing_pipeQA -s
echo "----------------------------------------"
eups list -s
echo "----------------------------------------"

# Setup a package containing all git-packages in order to 
# build a one pass dependency tree of all DM packages
#     Setup the $MANIFEST packages so the dependencies are acquired 
#     from the brand-new source tables not past-due-date packages
rm -rf StackTop
mkdir -p StackTop/ups
cp /dev/null StackTop/ups/StackTop.table
while read LINE; do
    set $LINE
    #setup -v -j $1 $2
    echo "setupRequired($1 $2)"  >>StackTop/ups/StackTop.table
done < $MANIFEST
eups declare -r StackTop StackTop stackTopDeps
setup -j  StackTop stackTopDeps

# Determine the topo dependency tree to use as build sequence of all packages
eups list --raw -s -D --topo StackTop > $ALL_PKG_BUILD_ORDER_MANIFEST.rawTopo
if [ $? != 0 ]; then
    echo "FAILURE to extract dependency manifest from package: StackTop.\n Check for dependency cycle."
    exit $BUILDBOT_FAILURE
fi
cat $ALL_PKG_BUILD_ORDER_MANIFEST.rawTopo | tac | sed -e "s/|.*//g" | grep -v StackTop > $ALL_PKG_BUILD_ORDER_MANIFEST

#
# now build the dependency lists for each setup DM package
while read LINE; do
    set $LINE
    base_package=$1
    base_version=$2
    base_path="git/$base_package/$base_version"
    echo "creating manifest for package: $base_package  $base_version"
    # new version of eups w/cyclic depdency check is not installed
    #eups list --raw -s -D --topo --check $base_package $base_version | tac > $base_path/eups_topo.list
    eups list --raw -s -D --topo $base_package $base_version | tac > $base_path/eups_topo.list
    if [ $? != 0 ]; then
        echo "FAILURE to extract dependency manifest from package: $base_package.\nCheck for dependency cycle."
        exit $BUILDBOT_FAILURE
    fi
    cat $base_path/eups_topo.list | sed -e "s/|/ /g" > $base_path/manifest

    rm -f $base_path/internal.deps
    rm -f $base_path/external.deps
    while read PACKAGE_MANIFEST; do
        set $PACKAGE_MANIFEST
        local_package=$1
        local_version=$2
        checkManifestPackage="`grep -w $local_package $MANIFEST | awk '{print $1}'`"
        if [ "$local_package" = "$checkManifestPackage" ]; then
             echo "$local_package $local_version" >> $base_path/internal.deps
        else
             echo "$local_package $local_version" >> $base_path/external.deps
        fi
    done < $base_path/manifest
done < $MANIFEST


# /\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\
# BUG NOTE:  Should a change in 3rd party package versions initiate a rebuild of
# BUG NOTE:  all DM packages which depend on them?
# /\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\

# Exclude 3rd party packages from $ALL_PKG_BUILD_ORDER_MANIFEST 
echo "================================================"
echo "Building DM-only package list in dependency sorted order from $MANIFEST"
rm -f $DM_PKG_BUILD_ORDER_MANIFEST
while read LINE; do
    set $LINE
    package=$1
    check_dm_pkg_manifest="`grep -w $package $MANIFEST | awk '{print $1,$2}'`"
    if [ "$package" = "`echo $check_dm_pkg_manifest| awk '{print $1}'`" ] ; then
        echo "$check_dm_pkg_manifest" >> $DM_PKG_BUILD_ORDER_MANIFEST
    fi
done < $ALL_PKG_BUILD_ORDER_MANIFEST

if [ ! -e $DM_PKG_BUILD_ORDER_MANIFEST ] ; then
    echo "FAILURE to find any DM packages in $ALL_PKG_BUILD_ORDER_MANIFEST;\n this indicates a bug in the process."
    exit $BUILDBOT_FAILURE
fi

echo "================================================"
echo "DM-only package list in dependency sorted order"
cat $DM_PKG_BUILD_ORDER_MANIFEST
echo "================================================"


# Finally update up-stream packages to be rebuilt if a dependency of theirs
# changed.  This process assumes package StackTop's dependency list 
# (aka $DM_PKG_BUILD_ORDER_MANIFEST) is in one-pass build sequence order. 

while read BASE; do
    set $BASE
    base_package=$1
    base_version=$2
    echo "------------------------------------------------------------------"
    echo "Check all higher level packages which might depend on $base_package"
    ls git/$base_package/$base_version/NEEDS_BUILD
    if [ ! -e git/$base_package/$base_version/NEEDS_BUILD ]; then
        continue
    fi

    # Now skip through roster until past the base_package, then for each 
    # subsequent package, set NEEDS_BUILD and remove BUILD_OK if necessary
    SKIP=0
    while read REQUIRED_BY; do
        set $REQUIRED_BY
        if [ "$base_package" = "$1" ] ; then
            SKIP=1
            continue
        elif [ $SKIP = 0 ] ; then
            continue
        fi
        required_by_package=$1
        required_by_version=$2
        required_by_path="git/$required_by_package/$required_by_version"

        # check if package's manifest depends on base_package
        check_pkg_manifest="`grep -w $base_package $required_by_path/internal.deps | awk '{print $1}'`"
        if [ "$base_package" = "$check_pkg_manifest" ] ; then
            echo "Updating $required_by_package  need to rebuild"
            touch $required_by_path/NEEDS_BUILD
            rm -f $required_by_path/BUILD_OK
        fi
    done < $DM_PKG_BUILD_ORDER_MANIFEST
done < $DM_PKG_BUILD_ORDER_MANIFEST


#if [ $? != 0 ]; then
#    exit $BUILDBOT_FAILURE
#fi
exit $BUILDBOT_SUCCESS
