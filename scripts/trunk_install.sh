#! /bin/bash
# install a requested package from version control, and recursively
# ensure that its minimal dependencies are installed likewise

usage() {
#80 cols  ................................................................................
    echo "Usage: $0 [options] package version"
    echo "Install a requested package from version control, and recursively"
    echo "ensure that its minimal dependencies are installed likewise."
    echo
    echo "Options (must be in this order):"
    echo "          -verbose: print out extra debugging info"
    echo "            -force: if the package is already installed, re-install it"
    echo "  -against_current: build against current versions of dependencies"
    echo "                    instead of minimal versions"
    echo "         -indent N: spaces to indent output as a hint to recursion depth"
    echo "   -chain <prefix>: a string representing the installation recursion state"
    echo " -dont_log_success: if specified, only save logs if install fails"
    echo "  -log_dest <dest>: scp destination for config.log,"
    echo "                    for example \"buildbot@master:/var/www/html/logs\""
    echo "    -log_url <url>: URL prefix for the log destination,"
    echo "                    for example \"http://master/logs/\""
    echo "           version: trunk - the latest trunk version from SVN"
    echo "                    current - the version in current.list"
    echo "                    svn#### - svn revision ####"
    echo "                    arbitrary - any legitimate released version of a package"
}
source /lsst/stacks/default/loadLSST.sh
source ${0%/*}/build_functions.sh


DEV_SERVER="lsstdev.ncsa.uiuc.edu"
SVN_SERVER="svn.lsstcorp.org"
WEB_ROOT="/var/www/html/doxygen"

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
if [ "$1" = "-against_current" ]; then
    AGAINST_CURRENT=$1
    shift
fi
if [ ! "$1" ]; then
    usage
    exit 1
fi

if [ "$1" = "-indent" ]; then
    INDENT=$2
    shift 2
fi

if [ "$1" = "-chain" ]; then
    INCOMING_CHAIN=$2
    shift 2
fi

if [ "$1" = "-dont_log_success" ]; then
    shift
else
    LOG_SUCCESS="true"
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

PACKAGE=$1
RAW_PACKAGE=$PACKAGE # without devenv_ stripped off the front
CHAIN=$INCOMING_CHAIN:$PACKAGE

TABLE_FILE_PREFIX=$PACKAGE

#----------------------------------------------------------------------
#----------------------------------------------------------------------
#RAA   F I X   F I X   when LSSTPipe subversion is updated to 1.6+     F I X
# Prefer to use system resident svn 1.6+ instead of LSSTPipe svn 1.5
pretty_execute unsetup subversion
#----------------------------------------------------------------------
#----------------------------------------------------------------------


# -------------------
# -- special cases -- la la la I can't hear you
# -------------------
if [ $PACKAGE = "scons" ]; then
    TABLE_FILE_PREFIX="sconsUtils" # ignore scons.table
    print "special case: use $TABLE_FILE_PREFIX.table and ignore $PACKAGE.table"
fi
if [ ${PACKAGE:0:7} = "devenv_" ]; then
    print "special case: $PACKAGE means ${PACKAGE:7}"
    PACKAGE=${PACKAGE:7}
    TABLE_FILE_PREFIX=$PACKAGE
fi
#if [ $PACKAGE = "sconsUtils" ]; then
#    print "package $PACKAGE is redundant with scons; skipping"
#    exit 0
#fi

# ------------------------
# -- figure out version --
# ------------------------
step "Determine version of $PACKAGE to test"

package_is_external $PACKAGE
if [ $? = 0 ]; then EXTERNAL=true; fi

SYMBOLIC_VERSION=$2
if [ ! "$SYMBOLIC_VERSION" ]; then
    print "Please specify a version."
    usage
    exit 1
fi
if [ "$SYMBOLIC_VERSION" = "current" ]; then
    lookup_current_version $PACKAGE
    VERSION=$RET_CURRENT_VERSION
    INSTALL_FROM_SVN=true
else
    VERSION=$SYMBOLIC_VERSION
fi

# decide whether to install with lsstpkg or from svn with scons
#
# For now, due to fragility in SVN versions of release packages,
# we use lsstpkg to install all non-trunk and non-svn####
# packages.  Hopefully, regular use of this test script will help
# firm things up, so that we can use SVN in the future for all
# internal packages.
#
# TODO: switch to SVN for all release versions of internal packages?
if [ $SYMBOLIC_VERSION = "trunk" -o "${VERSION:0:3}" = "svn" ]; then
    INSTALL_FROM_SVN="true"
    if [ "$EXTERNAL" ]; then
	# external packages should always be current or a specific non-svn version
	print "Unexpected version for external package $PACKAGE: $SYMBOLIC_VERSION ($VERSION)"
	exit 1
    fi
fi

print "package = $PACKAGE; version = $VERSION"

# --------------------------------
# -- prep current install state --
# --------------------------------
# install external & tagged packages (including current) with lsstpkg
if [ ! "$INSTALL_FROM_SVN" ]; then
    step "Install release package $PACKAGE $VERSION"
    # eups list $PACKAGE
    INSTALL_CMD="lsstpkg install $PACKAGE $VERSION"
    pretty_execute $INSTALL_CMD
    if [ $RETVAL != 0 ]; then
	print "Failed to install $PACKAGE $VERSION with lsstpkg."
	if [ $EXTERNAL ]; then
	    exit 1
	else
	    print "Will check out from tag and install with scons."
	    INSTALL_FROM_SVN=true
	fi
    else
	print "$PACKAGE successfully installed."
	print "Package $PACKAGE $VERSION is tagged or external; no need to test dependencies"
	exit 0
    fi
fi

# ------------------------
# -- check out from svn --
# ------------------------
svn_url $RAW_PACKAGE $VERSION
SVN_URL=$RET_SVN_URL
SVN_ADDL_ARG=$RET_SVN_ADDL_ARGS
REVISION=$RET_REVISION

mkdir -p svn
SVN_LOCAL_DIR=svn/${PACKAGE}_${VERSION}

# if force, remove existing package
if [ "$FORCE" -a -d $SVN_LOCAL_DIR ]; then
    lookup_svn_revision $SVN_LOCAL_DIR
    print "Remove existing $PACKAGE $VERSION"
    pretty_execute "eups remove --force $PACKAGE svn$RET_REVISION"
    # remove svn dir, to force re-checkout
    pretty_execute "rm -rf $SVN_LOCAL_DIR"
fi

if [ ! -d $SVN_LOCAL_DIR ]; then
    step "Check out $PACKAGE $VERSION from $SVN_URL"
    SVN_COMMAND="svn checkout $SVN_URL $SVN_LOCAL_DIR $SVN_ADDL_ARGS"
else
    step "Update $PACKAGE $VERSION from svn"
    SVN_COMMAND="svn update $SVN_LOCAL_DIR $SVN_ADDL_ARGS"
fi
print "Extracting source: $SVN_COMMAND"
pwd
pretty_execute "$SVN_COMMAND"
if [ $RETVAL != 0 ]; then
    print "svn checkout or update failed; is $PACKAGE $VERSION a valid version?"
    exit 1
fi

step "Prepare dependencies"
# --------------------------------------
# -- collect and install dependencies --
# --------------------------------------
# To Do: switch to use "eups list <package> <version> --dependencies --depth ==1"
# (when Robert releases the next version of eups)
TABLE_FILE="$SVN_LOCAL_DIR/ups/$TABLE_FILE_PREFIX.table"
if [ ! -f $TABLE_FILE ]; then
    print "Table file $TABLE_FILE doesn't exist."
    exit 1
fi

# split lines of table file
OLD_IFS=$IFS
IFS=${IFS:2:3} # hack -- newline is the third char in default IFS
NUM_DEPS=0
unset DEPS
unset DEPENDENCIES
# sed: strip off leading spaces and tabs
for DEP_LINE in `grep -P setupRequired\|setupOptional $TABLE_FILE | sed 's/^[ \t]*//'`; do
    DEPS[$NUM_DEPS]=$DEP_LINE
    let "NUM_DEPS += 1"
done
IFS=$OLD_IFS

# extract dependency names & versions from lines of table file
# recursively install each dependency and call setup
I=0
while [ $I -lt $NUM_DEPS ]; do
    # of the form setupRequired(coral >= 1_9_0+1), maybe with leading spaces
    DEP=${DEPS[$I]}
#    if [ `expr match "$DEP" "setupRequired(.+)"` ]; then
    if [ ${DEP:0:13} == "setupRequired" ]; then
	unset DEP_OPTIONAL
	EXTRACTED=${DEP#*setupRequired(} # trim off prefix
    elif  [ ${DEP:0:13} == "setupOptional" ]; then
	DEP_OPTIONAL="true"	
	EXTRACTED=${DEP#*setupOptional(} # trim off prefix
    else
	print "unexpected format in $TABLE_FILE: '$DEP'"
	exit 1
    fi
    EXTRACTED=${EXTRACTED%)*} # trim off suffix
    EXTRACTED=${EXTRACTED#\"} # trim off leading double quote
    EXTRACTED=${EXTRACTED%\"} # trim off trailing double quote
    
    # separate version and name of dependency
    split $EXTRACTED
    N=${#RET[*]}
    DEPENDENCY=${RET[0]}
    
    if [ "$DEP_OPTIONAL" ]; then
	DEP_VERSION=""
	J=0
	# Check for special case: listed in both required and optional.  For
	# example, in ip_isr, pex_harness is both, with a specific version
	# listed as required.  We'll let the required version supercede the
	# optional version, and treat it as required for now.
	while [ $J -lt $I ]; do
	    if [ "${DEPENDENCIES[$J]}" == "$DEPENDENCY" ]; then
		print "$DEPENDENCY is listed as both setupRequired and setupOptional; treating as setupRequired(${DEP_VERSIONS[$J]})."
		DEP_VERSION=${DEP_VERSIONS[$J]} # supercede optional version
		unset DEP_OPTIONAL # treat this package as required
	    fi
	    let "J += 1"
	done
    elif [ $N = 1 ]; then # setupRequired(dep)
	lookup_current_version $DEPENDENCY
	DEP_VERSION=$RET_CURRENT_VERSION
    elif [ $N = 2 ]; then # setupRequired(dep 3.0)
	DEP_VERSION=${RET[1]}
    elif [ $N = 3 ]; then # setupRequired(dep >= 3.0)
	if [ ${RET[1]} = ">" ]; then
	    # 1. if current version is newer than the inadequate version, then use the current version
	    lookup_current_version $DEPENDENCY
	    pick_newest_version $RET_CURRENT_VERSION ${RET[2]}
	    debug "Checking dependency $EXTRACTED.  Current version is $RET_CURRENT_VERSION; inadequate version is ${RET[2]}."
	    # note: watch out for case where current version is equal to inadequate version
	    if [ "$RET_NEWEST_VERSION" == "$RET_CURRENT_VERSION" -a "$RET_CURRENT_VERSION" != "${RET[2]}" ]; then
		DEP_VERSION=$RET_CURRENT_VERSION
		print "Found dependency $EXTRACTED: current version ($RET_CURRENT_VERSION) is sufficient."
	    # 2. if the current version is equal to or older than the inadequate version, then use trunk version
	    else
		lookup_svn_trunk_revision $DEPENDENCY
		DEP_VERSION="svn$RET_REVISION"
		print "Found dependency $EXTRACTED: assuming trunk version ($DEP_VERSION)."
	    fi
	elif [ ${RET[1]} = ">=" -o ${RET[1]} = "=" -o ${RET[1]} = "==" ]; then
	    DEP_VERSION=${RET[2]}
	else
	    print "Unsupported comparison in '$DEP': '${RET[1]}'"
	    exit 1
	fi
    else
	print "Unable to parse dependency '$DEP'"
	exit 1
    fi

    # if building against current, but required version is newer, use newer
    if [ "$AGAINST_CURRENT" -a ! "$DEP_OPTIONAL" ]; then # coerced to current
	# pick newest of (current, minimum) so that if an old version is listed
	# as minimum, we'll use the current, but if a newer-than-current version
	# is specified, we'll use that instead
	lookup_current_version $DEPENDENCY
	pick_newest_version $DEP_VERSION $RET_CURRENT_VERSION
	DEP_VERSION=$RET_NEWEST_VERSION
    fi

    # remember for setup step later
    DEPENDENCIES[$I]=$DEPENDENCY
    DEP_VERSIONS[$I]=$DEP_VERSION
    DEP_OPTIONALS[$I]=$DEP_OPTIONAL

    # already installed?  If not, install it
    if [ `eups list $DEPENDENCY $DEP_VERSION | wc -l` = 1 ]; then
	debug "Dependency $DEPENDENCY $DEP_VERSION is already installed."
#	setup $DEPENDENCY $DEP_VERSION
    else
	if [ ! "$DEP_OPTIONAL" ]; then
            # recursively install dependency
	    NEW_INDENT=$INDENT
	    let "NEW_INDENT += 4"
	    print "Recursively installing $DEPENDENCY $DEP_VERSION"
	    RECURSE_CMD="$0 $AGAINST_CURRENT -indent $NEW_INDENT -chain $CHAIN $LOG_ARGS $DEPENDENCY $DEP_VERSION"
            debug $RECURSE_CMD
            $RECURSE_CMD
	    if [ $? != 0 ]; then
		print "Installation of $DEPENDENCY $DEP_VERSION failed"
		exit 1
	    fi
	fi
    fi

    let "I += 1"
done

# --------------------------------------------
# -- setup precise versions of dependencies --
# --------------------------------------------
if [ "$AGAINST_CURRENT" ]; then
    print "Building against CURRENT versions of dependencies (not minimal versions)."
else
    print "Building against MINIMAL versions of dependencies (not current versions)."
fi
I=0
while [ $I -lt $NUM_DEPS ]; do
    if [ "${DEP_OPTIONALS[$I]}" ]; then
	if [ `eups list ${DEPENDENCIES[$I]} | wc -l` != 0 ]; then
	    print "Optional dependency ${DEPENDENCIES[$I]} is available."
	    pretty_execute "setup ${DEPENDENCIES[$I]}"
	else
	    print "Optional dependency ${DEPENDENCIES[$I]} is not available; skipping."
	fi
    elif [ ${DEP_VERSIONS[$I]} = "current" ]; then
	print "${DEPENDENCIES[$I]}: using current version."
	pretty_execute "setup ${DEPENDENCIES[$I]}"
    else
	pretty_execute "setup ${DEPENDENCIES[$I]} ${DEP_VERSIONS[$I]}"
	if [ $RETVAL != 0 ]; then
	    print "Failed to $DEP_SETUP_CMD"
	    exit 1
	fi
    fi
    let "I += 1"
done

# print versions of dependencies
I=0
echo
while [ $I -lt $NUM_DEPS ]; do
    print "${DEPENDENCIES[$I]} `eups list -s ${DEPENDENCIES[$I]}`"
    let "I += 1"
done

step "Install $PACKAGE $VERSION"
# ------------------
# -- setup self --
# ------------------
pushd $SVN_LOCAL_DIR > /dev/null
#pretty_execute "eups list -s | grep scons # BEFORE setup"
#pretty_execute "eups list -s # BEFORE setup"
pretty_execute "setup -r ."
#pretty_execute "setup -r . --exact"
#pretty_execute "eups list -s | grep scons # AFTER setup"
#pretty_execute "eups list -s # AFTER setup"
pretty_execute "eups list $PACKAGE"
if [ $RETVAL != 0 ]; then
    print "Failed to setup $PACKAGE $VERSION"
    exit 1
fi
popd > /dev/null

# prepare for stuff in self directory
pushd $SVN_LOCAL_DIR > /dev/null

# ------------------
# -- install self --
# ------------------
debug "Clean up previous attempt"
quiet_execute scons -c
scons_tests $PACKAGE
pretty_execute "scons opt=3 install $SCONS_TESTS declare"
#pretty_execute "scons opt=3 -j 2 force=true install $SCONS_TESTS declare"
SCONS_EXIT=$RETVAL
if [ $SCONS_EXIT != 0 ]; then
    print "Install/test failed: $PACKAGE $VERSION"
    FAILED_INSTALL=true
fi

# Why would we want to eups declare this package?  I don't see a reason.
# setup -r . && scons should be enough.
#
# pretty_execute "eups declare -r . $PACKAGE $VERSION"
# # if no current version of self, declare self current
# pretty_execute "eups list -c $PACKAGE | grep Current"
# if [ ! "`eups list -c $PACKAGE | grep Current`" ]; then
#     print "No version of $PACKAGE is declared current; declaring $VERSION current."
#     pretty_execute eups declare -c $PACKAGE $VERSION
# fi

# preserve logs
LOG_FILE="config.log"
pretty_execute pwd
if [ "$LOG_DEST" -a "(" "$FAILED_INSTALL" -o "$LOG_SUCCESS" ")" ]; then
    if [ -f "$LOG_FILE" ]; then
	copy_log ${PACKAGE}_$VERSION/$LOG_FILE $LOG_FILE $LOG_DEST_HOST $LOG_DEST_DIR $PACKAGE/$VERSION $LOG_URL
    else
	print "No $LOG_FILE present."
    fi
else
    if [ -f "$LOG_FILE" ]; then
	print "Not preserving config.log."
    else
	print "No config.log generated."
    fi
fi

if [ $VERSION = "trunk" ]; then
    # ------------------
    # -- copy doxygen -- (only trunk -- tagged releases are handled by nightly fresh install)
    # ------------------
    if [ -d $WEB_ROOT ]; then
	HTML_DIR=$WEB_ROOT/trunk/$PACKAGE
	if [ -d doc/htmlDir ]; then
	    step "Copying Doxygen docs to web server"
	    if [ -d $HTML_DIR ]; then
		rm -rf $HTML_DIR
	    fi
	    pretty_execute -anon mkdir -m 755 -p $HTML_DIR
	    pretty_execute -anon cp -r doc/htmlDir/* $HTML_DIR
	    pretty_execute -anon chmod 644 $HTML_DIR/*
	fi
    else
	print "Not copying Doxygen docs - $WEB_ROOT does not exist"
    fi
fi

if [ $VERSION = "trunk" -a ! "$FAILED_INSTALL" ]; then
    # ----------------------------
    # -- check for failed tests --
    # ----------------------------
    step "Checking for failed tests"
    if [ -d tests ]; then
	FAILED_COUNT=`find tests -name "*.failed" | wc -l`
	if [ $FAILED_COUNT != "0" ]; then
	    print "Some tests failed:"
	    pretty_execute -anon 'find tests -name "*.failed"'
	    # cat .failed files to stdout
	    for FAILED_FILE in `find tests -name "*.failed"`; do
		pretty_execute "cat $FAILED_FILE"
	    done
	    FAILED_INSTALL=true
	else
	    print "All tests succeeded in $PACKAGE"
	fi
    else
	print "No tests found in $PACKAGE"
    fi
fi

# done with stuff in self directory
popd > /dev/null

# -----------------------------------------
# -- Remove any remaining trunk packages --
# -----------------------------------------
# Note: only do this from root of recursive install -- that is, if chain is
# empty
if [ ! "$INCOMING_CHAIN" ]; then
    step "Build provenance of $PACKAGE"
    pretty_execute "eups list -s"
    pretty_execute "gcc -v"

    #pretty_execute "ls svn # before"
    step "Remove trunk packages"
    count_trunk_packages
    while [ $TRUNK_PACKAGE_COUNT != "0" ]; do
	PREV_COUNT=$TRUNK_PACKAGE_COUNT
	remove_trunk_packages
	count_trunk_packages
	debug "Trunk package count = $TRUNK_PACKAGE_COUNT (previously $PREV_COUNT)"
	#pretty_execute "ls svn # during"
	if [ $TRUNK_PACKAGE_COUNT = $PREV_COUNT -a $TRUNK_PACKAGE_COUNT != "0" ]; then
	    FAILED_INSTALL=true
	    print "Failed to remove all trunk packages.  Some remain:"
	    eups list | grep svn | grep -v LOCAL
	    break
	fi
    done
    #pretty_execute "ls svn # after"
fi

if [ "$FAILED_INSTALL" ]; then
    print "Installation of $PACKAGE $VERSION failed."
    exit 1
else
    print "Installation of $PACKAGE $VERSION succeeded."
    exit 0
fi
