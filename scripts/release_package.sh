#! /bin/bash
# install a release package and all of its dependencies, using lsstpkg

if [[ $1 == "" ]]
then
    echo "usage: $0 [-lsstdir dir] [-C] package [packages to check]"
    exit 1
fi

source ${0%/*}/build_functions.sh

WEB_ROOT=/var/www/html/doxygen

# URL for package list, in install order
# http://dev.lsstcorp.org/dmspkgs/manifests/LSSTPipe.manifest

# figure out LSST dir
if [[ $1 == "-lsstdir" ]]
then
    LSST_DIR=$2
    export LSST_HOME=$LSST_DIR
    shift
    shift
else
    LSST_DIR="."
    export LSST_HOME=`pwd`
fi

if [ "$1" = "-C" ]; then
    EXTRA_ARGS=$1;
    shift
fi

INSTALL_PACKAGE=$1

step "installing LSST package '$INSTALL_PACKAGE'"

source $LSST_DIR/loadLSST.sh
if [ $? != 0 ]; then
    echo "loadLSST.sh failed"
    exit 1
fi
pretty_execute lsstpkg $EXTRA_ARGS install $INSTALL_PACKAGE
INSTALL_SUCCEEDED=$RETVAL
if [ $INSTALL_SUCCEEDED != 0 ]; then
    echo "install $INSTALL_PACKAGE failed"
    eups list -s
#    echo "-------------------- `find . -name build.log` --------------------"
#    cat `find . -name build.log`
#    echo "-------------------- `find . -name config.log` --------------------"
#    cat `find . -name config.log`
#    exit 1
fi

# check for packages
if [ $INSTALL_SUCCEEDED == 0 ]; then
    step "Check for installed packages"
    for CHECK_PACKAGE in $@
      do
      if [ $CHECK_PACKAGE != "LSSTPipe" ]; then # a phantom package
	  PACKAGE_COUNT=`eups list $CHECK_PACKAGE | wc -l`
	  if [ $PACKAGE_COUNT = "1" ]; then
	      echo "  - Package '$CHECK_PACKAGE' is present."
	  elif [ $PACKAGE_COUNT = "0" ]; then
	      echo "  - Package '$CHECK_PACKAGE' is not installed:";
	      eups list
	      exit 1 # failed - no package installed
	  else
	      echo "  - Unexpected: found more than one $CHECK_PACKAGE installed:";
	      pretty_execute "eups list $CHECK_PACKAGE"
	      exit 1
	  fi
      fi
    done
fi

# only copy docs if this machine has a /var/www/html/doxygen
step "Copy doxygen docs to www:"
if [ -d $WEB_ROOT ]; then
    for DOC_DIR in `find . -wholename \*doc/doxygen -o -wholename \*doc/htmlDir`; do
	OLD_IFS=$IFS
	IFS="/" # now bash will split on / instead of white space
	I=0
	for PATH_ELEM in $DOC_DIR; do
#	    echo "      + $PATH_ELEM"
	    ELEMS[I]=$PATH_ELEM
	    I=$I+1
	done
	PACKAGE_NAME=${ELEMS[2]}
	PACKAGE_VERSION=${ELEMS[3]}
	echo "  - $PACKAGE_NAME v$PACKAGE_VERSION"
	IFS=$OLD_IFS # restore default splitting behavior

	WWW_DIR=$WEB_ROOT/release/$PACKAGE_NAME/$PACKAGE_VERSION
	WWW_CURRENT=$WEB_ROOT/release/$PACKAGE_NAME/current
	if [ -d $WWW_DIR ]; then
	    echo "    $WWW_DIR already exists; not overwriting"
	else
	    echo "    $WWW_DIR Doesn't exist; copying docs"
	    mkdir -m 755 -p $WWW_DIR
	    cp -r $DOC_DIR/* $WWW_DIR
	    chmod 644 $WWW_DIR/*
	fi
	# could move symlinking into the else block, but keep it for now to
	# catch the ones we missed
	rm -f $WWW_CURRENT
	ln -s $WWW_DIR $WWW_CURRENT
    done
else
    echo "Not copying Doxygen docs - $WEB_ROOT does not exist"
fi

step "Build provenance:"
# build provenance info
pretty_execute "gcc -v"
pretty_execute "eups list"

exit $INSTALL_SUCCEEDED