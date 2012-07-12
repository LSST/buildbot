#! /bin/bash
# install a release package and all of its dependencies, using lsstpkg

# Installation of Release Packages should occur in either:
#  * the system space or 
#  * alternate space named by: '-lsstdir' parameter
# Syntax: $0 [--lsstdir dir]  [--no_doxygen] [--tag current] [--astro_net_data data --astro_net_data_dir data_dir] package [packages to check]

source ${0%/*}/gitConstants.sh

options=$(getopt -l no_doxygen,tag:,astro_net_data:,astro_net_data_dir:,lsstdir: -- "$@")

ASTROMETRY_NET_DATA=""
ASTROMETRY_NET_DATA_DIR=""
LSST_DIR=""
EXTRA_ARGS=""

while true
do
    case $1 in
        --no_doxygen) NO_DOXYGEN=true; shift;;
        --astro_net_data) ASTROMETRY_NET_DATA=$2; shift 2;;
        --astro_net_data_dir) ASTROMETRY_NET_DATA_DIR=$2; shift 2;;
        --tag) EXTRA_ARGS="--tag=$2"; shift 2;;
        --lsstdir) LSST_DIR=$2; export LSST_HOME=$LSST_DIR; shift 2;;
        *) [ "$*" != "" ] && echo "parsed options; arguments left are:$*:"
             break;;
    esac
done

if [ "x$LSST_DIR" = "x" ]; then
    LSST_DIR="."
    export LSST_HOME=`pwd`
fi

if [ "x$ASTROMETRY_NET_DATA" = "x" ] && [ "x$ASTROMETRY_NET_DATA_DIR" = "x" ] ; then
    echo -n ""
elif [ "x$ASTROMETRY_NET_DATA" != "x" ] && [ "x$ASTROMETRY_NET_DATA_DIR" != "x" ] ; then
    echo -n ""
else
    echo "FATAL: Usage: $0 [--lsstdir dir]  [--no_doxygen] [--tag current] [--astro_net_data data --astro_net_data_dir data_dir] package [packages to check]"
    exit $BUILDBOT_FAILURE
fi


source ${0%/*}/build_functions.sh

WEB_ROOT=/var/www/html/doxygen

# URL for package list, in install order
# http://dev.lsstcorp.org/dmspkgs/manifests/LSSTPipe.manifest


INSTALL_PACKAGE=$1

step "installing LSST package '$INSTALL_PACKAGE'"

print "Before loadLSST.sh: LSST_HOME: $LSST_HOME   LSST_DEVEL: $LSST_DEVEL"
print "Before loadLSST.sh: EUPS_PATH: $EUPS_PATH"
source $LSST_DIR/loadLSST.sh
if [ $? != 0 ]; then
    echo "FATAL: loadLSST.sh failed."
    exit $BUILDBOT_FAILURE
fi
print "After loadLSST.sh: LSST_HOME: $LSST_HOME  LSST_DEVEL: $LSST_DEVEL"
print "After loadLSST.sh: EUPS_PATH: $EUPS_PATH"
for DIR in $LSST_HOME $LSST_DEVEL; do
    eups admin clearCache -Z $DIR
    if [ $? != 0 ] ; then
        echo "FATAL: \"eups admin clearCache -Z $DIR\" failed."
        exit $BUILDBOT_FAILURE
    fi
    eups admin buildCache -Z $DIR
    if [ $? != 0 ] ; then
        echo "FATAL: \"eups admin buildCache -Z $DIR\" failed."
        exit $BUILDBOT_FAILURE
    fi
done

if [ "$ASTROMETRY_NET_DATA" ]; then
	eups declare astrometry_net_data $ASTROMETRY_NET_DATA -r $ASTROMETRY_NET_DATA_DIR
fi

echo "eups -v -v -v  --debug=raise distrib install $EXTRA_ARGS $INSTALL_PACKAGE"
eups -v -v -v  --debug=raise distrib install $EXTRA_ARGS $INSTALL_PACKAGE
if [ $? != 0 ]; then
    echo "FATAL: install of: \"$INSTALL_PACKAGE\" failed."
    eups list -s
    exit $BUILDBOT_FAILURE
fi

# check for packages
step "Check for installed packages"
for CHECK_PACKAGE in $@ ; do
    if [ $CHECK_PACKAGE != "lsstactive" ]; then # a phantom package
	    PACKAGE_COUNT=`eups list $CHECK_PACKAGE | wc -l`
	    if [ $PACKAGE_COUNT = "1" ]; then
	        echo "INFO:  - Package \"$CHECK_PACKAGE\" is installed."
	    elif [ $PACKAGE_COUNT = "0" ]; then
	        echo "FATAL:  - Package \"$CHECK_PACKAGE\" is not installed:";
	        eups list
	        exit $BUILDBOT_FAILURE # failed - no package installed
	    else
	        echo "FATAL:  - Unexpected: found more than one: \"$CHECK_PACKAGE\" installed:";
	        pretty_execute "eups list $CHECK_PACKAGE"
	        exit $BUILDBOT_FAILURE
	    fi
    fi
done

# only copy docs if this machine has a /var/www/html/doxygen
step "Copy doxygen docs to www:"
if [ "$NO_DOXYGEN" ]; then
    echo "INFO: Not copying Doxygen docs by request."
elif [ -d $WEB_ROOT ]; then
    for DOC_DIR in `find . -wholename \*doc/doxygen -o -wholename \*doc/htmlDir | grep -v EupsBuildDir`; do
	OLD_IFS=$IFS
	IFS="/" # now bash will split on / instead of white space
	I=0
	for PATH_ELEM in $DOC_DIR; do
	    ELEMS[I]=$PATH_ELEM
	    I=$I+1
	done
	PACKAGE_NAME=${ELEMS[2]}
	PACKAGE_VERSION=${ELEMS[3]}
	echo "INFO:  - $PACKAGE_NAME v$PACKAGE_VERSION"
	IFS=$OLD_IFS # restore default splitting behavior

	WWW_DIR=$WEB_ROOT/release/$PACKAGE_NAME/$PACKAGE_VERSION
	WWW_CURRENT=$WEB_ROOT/release/$PACKAGE_NAME/current
	if [ -d $WWW_DIR ]; then
	    echo "INFO:    $WWW_DIR already exists; not overwriting"
	else
	    echo "INFO:    $WWW_DIR Doesn't exist; copying docs"
	    mkdir -m 755 -p $WWW_DIR
	    chmod 755 $WWW_DIR # should have happened in prev command -- why not?
	    cp -r $DOC_DIR/* $WWW_DIR
	    chmod 755 $WWW_DIR/*
	fi
	# could move symlinking into the else block, but keep it for now to
	# catch the ones we missed
	rm -f $WWW_CURRENT
	ln -s $WWW_DIR $WWW_CURRENT
    done
else
    echo "INFO: Not copying Doxygen docs - $WEB_ROOT does not exist"
fi

step "Build provenance:"
# build provenance info
pretty_execute "$CC -v"
pretty_execute "eups list"

exit $BUILDBOT_SUCCESS
