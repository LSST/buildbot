#==============================================================
# Set a global used for error messages to the buildbot guru
#==============================================================
BUCK_STOPS_HERE="srp@ncsa.uiuc.edu"

# See fetch_blame_data
BUILDBOT_BLAMEFILE="buildbot_tVt_blame"    # see fetch_blame_data


#---------------------------------------------------------------------------
# set $RET_CURRENT_VERSION to current version of $1, from current.list
lookup_current_version() {
    fetch_current_line $@
    RET_CURRENT_VERSION=${CURRENT_LINE[2]}
}

#---------------------------------------------------------------------------
# include "tests" in scons command?
# pass package name as argument; $SCONS_TESTS will either be "tests" or "",
# depending on whether the package is known not to support the "tests" target
scons_tests() {
    if [ $@ = "sconsUtils" -o $@ = "lssteups" -o $@ = "lsst" -o  $@ = "base" -o $@ = "security" ]; then
	SCONS_TESTS=""
    else
        SCONS_TESTS="tests"
    fi
}

#---------------------------------------------------------------------------
# look up the owners of a package in http://dev.lsstcorp.org/trac/wiki/PackageOwners?format=txt
# return result as PACKAGE_OWNERS
PACKAGE_OWNERS_URL="http://dev.lsstcorp.org/trac/wiki/PackageOwners"
fetch_package_owners() {
    local url="$PACKAGE_OWNERS_URL?format=txt"
    unset RECIPIENTS
    RECIPIENTS=`curl -s $url | grep "package $1" | sed -e "s/package $1://" -e "s/ from /@/g"`
    if [ ! "$RECIPIENTS" ]; then
	RECIPIENTS=$BUCK_STOPS_HERE
	print "*** Error: could not extract owner(s) of $1 from $url"
	print "*** Expected \"package $1: owner from somewhere.edu, owner from gmail.com\""
	print "*** Sending notification to $RECIPIENTS instead.\""
    fi
    PACKAGE_OWNERS=$RECIPIENTS
}

#---------------------------------------------------------------------------
# Clear global settings for blame data so next emailFailure doesn't use them
clear_blame_data() {
    unset BLAME_INFO
    unset BLAME_EMAIL
    unset BLAME_TMPFILE
}

#---------------------------------------------------------------------------
# $1 = git directory of package version which failed build.
# $2 - directory where a temp file can be stashed
# return result as RET_BLAME_EMAIL
fetch_blame_data() {
    local BLAME_PWD=`pwd`
    BLAME_TMPFILE="$2/$BUILDBOT_BLAMEFILE"
    BLAME_INFO=""
    if [ ! -d $1 ] ; then
         BLAME_EMAIL=""
         print "Problem fetching blame data: Bad git directory path: $1"
         return 0
    fi
    cd $1
    BLAME_EMAIL=`git log -1 --format='%ae'`
    if [ $? != 0 ] ; then
         BLAME_EMAIL=""
         print "Problem fetching blame data; git-log failure"
         cd $BLAME_PWD
         return 0
    fi
    touch  $BLAME_TMPFILE
    if [ $? != 0 ]; then
        print "Unable to create temp file: $BLAME_TMPFILE for blame details."
        BLAME_TMPFILE="/dev/null"
    fi
    git log --name-status --source -1 > $BLAME_TMPFILE
    cd $BLAME_PWD
    return 0
}


#---------------------------------------------------------------------------
# return 0 if $1 is external, 1 if not
package_is_external() {
    fetch_current_line $@
    local extra_dir=${CURRENT_LINE[3]}
    
    if [ "${extra_dir:0:8}" = "external" ]; then
	debug "$1 is an external package"
	return 0
    else
	debug "$1 is probably an internal LSST package"
	return 1
    fi
}

#---------------------------------------------------------------------------
# this is the GIT implemention of the scm_url routine.
#---------------------------------------------------------------------------
# $1 = raw package name (include devenv_ if present)
# $2 = version (3.1.2, svn3438) (optional)
# requires that SCM_SERVER be set already
# returns RET_SCM_URL, RET_REVISION
scm_url() {
    if [ ! "$SCM_SERVER" ]; then
	print "ERROR: no SCM server configured"
	return 1
    elif [ ! "$1" ]; then
	print "ERROR: no package specified"
	return 1
    fi
    # removed in the great git repository rename of 2011
    #scm_server_dir $1
    #RET_SCM_URL=git@$SCM_SERVER:LSST/DMS/$RET_SCM_SERVER_DIR.git
    RET_SCM_URL=git@$SCM_SERVER:LSST/DMS/$1.git
    if [ "$2" ] ; then
        RET_REVISION = $2
        return 0
    fi

    # Since version not supplied, will acquire master version id
    RET_REVISION=`git ls-remote --refs -h $RET_SCM_URL | grep refs/heads/master | awk '{print $1}'`
    if [[ $? != 0 ]]; then  
        print "Failed fetch of git master revision id for package $1. Exiting." 
        exit 1 
    fi
    return 0
}

#---------------------------------------------------------------------------
# $1 = package name
# sets RET_SCM_SERVER_DIR
scm_server_dir() {
    RET_SCM_SERVER_DIR=${1//_//} # replace all _ with / to derive directory from package name
    if [ $1 = "scons" ]; then # special case
	SCM_SERVER_DIR="devenv/sconsUtils"
    fi
    return 0
}

#---------------------------------------------------------------------------
# fetch $1's line from current.list, and set $CURRENT_LINE to its
# contents, as an array, split by white space
fetch_current_line() {
    debug "Look up current version of $1 in http://$DEV_SERVER/pkgs/std/w12/current.list"
    local current_list_url="http://$DEV_SERVER/pkgs/std/w12/current.list"
    local line=`curl -s $current_list_url | grep "^$1 "`
    if [ $? = 1 ]; then
	print "Couldn't fetch $current_list_url:"
	pretty_execute curl $current_list_url # print error code
    fi
    if [ "$line" == "" ]; then
# SRP - if no line exists for this package on the distribution server,
# shouldn't that be an error?  
# RAA -  No, think new dependency package in git not yet in current.list
#     - Need to check if git:<pkg> exists - fix up block below.
#  
#	print "no package '$1' listed in $current_list_url"
#	if [ "$SCM_SERVER" ]; then
#	    print "checking git repository instead"
#	    scm_url $1
#	    lookup_svn_revision $RET_SCM_URL
#	    if [ $? == 0 ]; then
#		# fake it with trunk version -- could use "trunk" as version instead
#		line="$1 generic svn$RET_REVISION"
#		#line="$1 generic trunk"
#	    fi
#	fi
        echo $1 "doesn't exist on the distribution server. exiting"
        exit 1
    fi
    if [ "$line" == "" ]; then
	print "unable to look up current version of $1 in $current_list_url or git"
	return 1
    fi
    # split on spaces
    local i=0
    # 0 name, 1 flavor, 2 version,
    # 3 extra_dir (either "external" or blank),
    # 4 pkg_dir (always blank)
    unset CURRENT_LINE
    for COL in $line; do
	CURRENT_LINE[$i]=$COL
	# print "${CURRENT_LINE[$i]} = ($COL)"
	let "i += 1"
    done
    # if version is "0", call it "trunk" instead
    if [ ${CURRENT_LINE[2]} == "0" ]; then
	CURRENT_LINE[2]="trunk"
    fi
    if [ ${CURRENT_LINE[0]} != $1 ]; then
	print "package name '$1' doesn't match first column '${CURRENT_LINE[0]}'"\
             "in current.list line:"
	print "    '$line'"
	return 1
    fi
}

#---------------------------------------------------------------------------
# parameter: line to split on spaces
# return: array, via RET
split() {
    local i=0
    unset RET
    for COL in $@; do
	RET[$i]=$COL
	# print "${RET[$i]} = ($COL)"
	let "i += 1"
    done
}

#---------------------------------------------------------------------------
# print a numbered header
STEP=1
step() {
    echo
    print "== $STEP. $1 == [ $CHAIN ]"
    let "STEP += 1"
}

#---------------------------------------------------------------------------
# print, with an indent determined by the command line -indent option
SPACES="                                                                   "
print() {
    echo "${SPACES:0:$INDENT}$@"
}

#---------------------------------------------------------------------------
# print, but only if -verbose or -debug is specified
debug() {
    if [ "$DEBUG" ]; then
	print $@
    fi
}

#---------------------------------------------------------------------------
# execute the command; if verbose, make its output visible
verbose_execute() {
    if [ "$DEBUG" ]; then
	pretty_execute $@
    else
	quiet_execute $@
    fi
}

#---------------------------------------------------------------------------
# print out the command and execute it, but pipe its output to /dev/null
# RETVAL is set to exit value
# prepend -anon to execute without displaying command
quiet_execute() {
    if [ "$1" = "-anon" ]; then
	local anon=true
	shift
    fi
    local cmd="$@ > /dev/null 2>&1"
    if [ "$anon" = "" ]; then print $cmd; fi
    eval $cmd
    RETVAL=$?
}

#---------------------------------------------------------------------------
# print a multi-line output in the same way as print()
# RETVAL is set to exit value
# prepend -anon to execute without displaying command
pretty_execute() {
    if [ "$1" = "-anon" ]; then
	local anon=true
	shift
    fi
    local spaces="${SPACES:0:$INDENT}"
    local awk_cmd_out="awk '{print \"$spaces  > \"\$0}'"
    local awk_cmd_err="awk '{print \"$spaces  - \"\$0}'"
    # This command doesn't work, because bash doesn't parse the "|"
    # properly in this context:
    # $@ | $awk_cmd
    # So we have to do this the hard way:
    local tmp_prefix="_tmp_build_functions_pretty"
    local tmp_cmd="${tmp_prefix}_cmd.tmp"
    local tmp_out="${tmp_prefix}_stdout.tmp"
    local tmp_err="${tmp_prefix}_stderr.tmp"
    if [ "$anon" = "" ]; then print $@; fi
    if [ -f $tmp_cmd -o -f $tmp_out -o -f $tmp_err ]; then
	#print "*** Unable to pretty-print: $tmp_cmd, $tmp_out, or $tmp_err exists. ***"
	$@
	RETVAL=$?
    else
	# save to buffer to preserve command's exit value (sending straight
	# to awk would give us awk's exit value, which will always be 0)
	local cmd="$@ > $tmp_out 2> $tmp_err"
	eval $cmd
	RETVAL=$?
	echo "cat $tmp_out | $awk_cmd_out" > $tmp_cmd
	source $tmp_cmd
	echo "cat $tmp_err | $awk_cmd_err" > $tmp_cmd
	source $tmp_cmd
	rm -f $tmp_cmd $tmp_out $tmp_err
    fi
}

#---------------------------------------------------------------------------
# params: file_description filename dest_host remote_dir additional_dir url
# for example copy_log config.log buildbot@tracula /var/www/html/logs /afw/trunk http://dev/buildlogs
copy_log() {
    local date_dir="`hostname`/`date +%Y`/`date +%m`/`date +%d`/`date +%H.%M.%S`"

    local file_description=$1
    local filename=$2
    local dest_host=$3
    local remote_dir=$4
    local additional_dir=$5
    local url=$6
    if [ ! "$6" ]; then
	print "not enough arguments to copy_log"
    elif [ "$7" ]; then
	print "too many arguments to copy_log"
    else
	local url_suffix=$additional_dir/$date_dir/$filename
	local remote_path=$remote_dir/$url_suffix
	local dest=$dest_host:$remote_dir/$url_suffix
	ssh $dest_host "mkdir -p $remote_dir/$additional_dir/$date_dir"
    echo "pwd is "$PWD
	#scp -q $filename $dest
    # put some HTML around the copied file so you it's formatted in the browser
    echo "<HTML><BODY><PRE>" >/tmp/foo.$$
    cat $filename >>/tmp/foo.$$
    echo "</PRE></BODY></HTML>" >>/tmp/foo.$$
	scp -q /tmp/foo.$$ $dest
    rm /tmp/foo.$$
    
	if [ $? != 0 ]; then
	    print "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	    print "!!! Failed to copy $filename to $dest"
	    print "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	else
	    ssh $dest_host "chmod +r $remote_path"
	    if [ $url ]; then
		# echo instead of print, because monitor class doesn't trim leading spaces
		echo "log file $file_description saved to $url/$url_suffix"
	    fi
	fi
    fi
}

#---------------------------------------------------------------------------
# outputs info used in e-mails to the blame list
scm_info() {

    echo "add scm_info for git here"
}

#---------------------------------------------------------------------------
# -- setup package's **trunk** scm directory in preparation for 
#        either extracting initial source tree to bootstrap dependency tree 
#        or the build  and install the accurate deduced dependency tree
# $1 = adjusted eups package name
# $2 = purpose of directory; one of: 
#         "BOOTSTRAP" :extracted directory only to be used for dependency tree
#         "BUILD" : extracted directory to be used for build
# return:  0, if svn checkout/update occured withuot error; 1, otherwise.
#       :  RET_REVISION
#       :  SCM_URL
#       :  REVISION 
#       :  SCM_LOCAL_DIR

prepareSCMDirectory() {

    # ------------------------------------------------------------
    # -- NOTE:  most variables in this function are global!  NOTE--
    # ------------------------------------------------------------

    if [ "$1" = "" ]; then
        print "No package name for git extraction. See LSST buildbot developer."
        RETVAL=1
        return 1
    fi

    if [[ "$2" != "BUILD" && "$2" != "BOOTSTRAP" ]]; then
        print "Failed to include legitimate purpose of directory extraction: $2. See LSST buildbot developer."
        RETVAL=1
        return 1
    fi

    local SCM_PACKAGE=$1 
    local PASS=$2

    # package is internal and should be built from trunk
    scm_url $SCM_PACKAGE
    local PLAIN_VERSION="$RET_REVISION"
    RET_REVISION="$RET_REVISION"
    SCM_URL=$RET_SCM_URL
    REVISION=$RET_REVISION

    print "Internal package: $SCM_PACKAGE will be built from trunk version: $PLAIN_VERSION"
   
    echo "working directory is $PWD" 
    mkdir -p git
    SCM_LOCAL_DIR="git/${SCM_PACKAGE}/${PLAIN_VERSION}"
    
    if [ -e $SCM_LOCAL_DIR ] ; then
        print "Local directory: $SCM_LOCAL_DIR exists, checking PASS: $PASS"
        if [ $PASS != "BUILD" ] ; then
            # Just need source directory to generate the dependency list so 
            # no need to clear build residue
                print "PASS!= BUILD so Dir only needed to generate the dependency list; no need to clear build residue."
            RETVAL=0
            return 0
        elif [ $PASS = "BUILD" ] ; then
            print "PASS=BUILD; now check if still NEEDS_BUILD."
            # Need source directory for build; now check its status
            if [ -f $SCM_LOCAL_DIR/NEEDS_BUILD ] ; then
                print "PASS=BUILD, NEEDS_BUILD, too; ready to build dir now."
                RETVAL=0
                return 0
            # Following should not be needed since this routine shouldn't be
            #   called if BUILD_OK exists in build dir.
            elif [ -f $SCM_LOCAL_DIR/BUILD_OK ] ; then
                print "PASS=BUILD, BUILD_OK so no need to rebuild."
                RETVAL=0
                return 0
            else # Danger: previous build failed, remove dir and re-extract
                print "PASS=BUILD but no BUILD_OK so must remove suspect build directory."
                if [ `eups list $SCM_PACKAGE $REVISION | grep -i setup | wc -l` = 1 ]; then
                    unsetup -j $SCM_PACKAGE $REVISION
                fi
                pretty_execute "eups remove -N $SCM_PACKAGE $REVISION"
                pretty_execute "rm -rf $SCM_LOCAL_DIR"
            fi
        fi
    fi

    # Now extract fresh source directory
    mkdir -p $SCM_LOCAL_DIR
    step "Check out $SCM_PACKAGE $REVISION from $SCM_URL"
    local SCM_COMMAND="git clone --depth=1 $SCM_URL $SCM_LOCAL_DIR "
    verbose_execute $SCM_COMMAND
    if [ $RETVAL = 1 ] ; then
       return 1
    fi

    # Set flag indicating ready for source build
    touch $SCM_LOCAL_DIR/NEEDS_BUILD
    if [ $? != 0 ]; then
        print "Unable to create temp file: $SCM_LOCAL_DIR/NEEDS_BUILD for prepareSCMDirectory."
        RETVAL=1
        return 1
    fi
    echo "SCM directory prepared"
    RETVAL=0
    return 0
}
