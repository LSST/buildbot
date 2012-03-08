#==============================================================
# Set a global used for error messages to the buildbot guru
#==============================================================
#BUCK_STOPS_HERE="srp@ncsa.uiuc.edu"
BUCK_STOPS_HERE="robyn@lsst.org"

# See fetch_blame_data
BUILDBOT_BLAMEFILE="buildbot_tVt_blame"    # see fetch_blame_data

# --
# Library Functions
# -----------------
# scons_tests() 
# fetch_package_owners() 
# clear_blame_data() 
# fetch_blame_data() 
# package_is_external()
# scm_url_to_package() 
# scm_url() 
# scm_server_dir() 
# fetch_current_line() 
# pretty_execute2() 
# scm_info() 
# saveSetupScript()
# prepareSCMDirectory() 
# --

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
	print_error "*** Error: could not extract owner(s) of $1 from $url"
	print_error "*** Expected \"package $1: owner from somewhere.edu, owner from gmail.com\""
	print_error "*** Sending notification to $RECIPIENTS instead.\""
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
    if [ ! -d "$1" ] ; then 
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
    if [ $? != 0 ]; then
        return 1
    fi
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
# this is the GIT implemention of the scm_url_to_package routine.
#---------------------------------------------------------------------------
# $1 = git repository url 
# returns: 
#  on success: SCM_PACKAGE = package name derived from git repository name
#              status = 0
#  on failure: SCM_PACKAGE = ""
#              status = 1
scm_url_to_package() {
local POSSIBLE=`echo $1 | sed -e "s/.*\/\(.*\).git$/\1/"`
if [ "$POSSIBLE" = "$1" ]; then
    SCM_PACKAGE=""
else
    SCM_PACKAGE="$POSSIBLE"
fi
print_error "scm_url_to_package: $SCM_PACKAGE"
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
        print_error "ERROR: no SCM server configured"
        return 1
    elif [ ! "$1" ]; then
	    print_error "ERROR: no package specified"
        return 1
    fi
    # removed in the great git repository rename of 2011
    #scm_server_dir $1
    RET_SCM_URL=git@$SCM_SERVER:LSST/DMS/$1.git
    # First verify URL addresses a real git repo.
    git ls-remote $RET_SCM_URL > /dev/null
    if [ $? != 0 ]; then
        print_error "Failed to find a git repository matching URL: $RET_SCM_URL"
        return 1
    fi
    # Note:  git ls-remote  has no option to ask about a specific commit-id.
    if [ "$2" ] ; then
        RET_REVISION = $2
        return 0
    fi

    # Since version not supplied, will acquire git-master version's commit id
    RET_REVISION=`git ls-remote --refs -h $RET_SCM_URL | grep refs/heads/master | awk '{print $1}'`
    if [ $? != 0 ]; then  
        print_error "Failed getting git master commit id for package $1." 
        return 1 
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
# $1 = package name; fetch $1's line from 'current.list'
# set $CURRENT_LINE to its contents, as an array, split by white space
fetch_current_line() {
    debug "Look up current version of $1 in $CURRENT_PACKAGE_LIST_URL"
    local current_list_url="$CURRENT_PACKAGE_LIST_URL"
    local line=`curl -s $current_list_url | grep "^$1 "`
    if [ $? = 1 ]; then
        print "Couldn't fetch $current_list_url:"
        pretty_execute curl $current_list_url # print error code
    fi
    if [ "$line" == "" ]; then
        print_error "unable to look up current version of $1 in $current_list_url"
        unset CURRENT_LINE
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
    if [ ${CURRENT_LINE[0]} != $1 ]; then
        print_error "package name '$1' doesn't match first column '${CURRENT_LINE[0]}'"\
             "in current package list line:"
        print_error "    '$line'"
        return 1
    fi
}


#---------------------------------------------------------------------------
pretty_execute2() {
set -x
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
	$@ > $tmp_out 2> $tmp_err
    if [ -f $tmp_out ]; then
        echo "output file created"
    else
        echo "output file NOT created"
    fi
    
	RETVAL=$?
	#echo "DEBUG: PWD = $PWD ; cat $tmp_out | $awk_cmd_out;tmp_cmd = $tmp_cmd"
	echo "cat $tmp_out | $awk_cmd_out" > $tmp_cmd
    chmod +x $tmp_cmd
	source $tmp_cmd
	echo "cat $tmp_err | $awk_cmd_err" > $tmp_cmd
	source $tmp_cmd
	#rm -f $tmp_cmd $tmp_out $tmp_err
    fi
set +x
}

#---------------------------------------------------------------------------
# outputs info used in e-mails to the blame list
scm_info() {

    echo "add scm_info for git here"
}

#---------------------------------------------------------------------------
# - save the setup script for this package in a directory developers can
#   use to reconstruct the buildbot environment.
# $1 = root directory
# $2 = eups package name
# $3 = build number
# $4 = failed build directory

# NOTE:  This is the way it was done before RHL suggested we could 
#        simplify it.  Below this is the refined version.
#saveSetupScript()
#{
#    echo "saving script to $1/setup/build$3/setup_$2.sh"
#    mkdir -p $1/setup/build$3
#    setup_file=$1/setup/build$3/setup_$2
#    eups list -s | grep -v LOCAL: | awk '{print "setup -j -v "$1" "$2}'| grep -v $2 >$setup_file.lst
#    echo "# This package failed. Note the hash tag, to debug against the correct version." >> $setup_file.lst
#    eups list -s | grep $2 | awk '{print "# setup -j -v "$1" "$2}' >>$setup_file.lst
#    RET_SETUP_SCRIPT_NAME=$setup_file.lst
#}

saveSetupScript()
{
    echo "saving script to $1/setup/build$3/setup_$2.sh"
    mkdir -p $1/setup/build$3
    setup_file=$1/setup/build$3/setup_$2
    eups list -s | grep -v LOCAL:  >$setup_file.lst
    RET_FAILED_PACKAGE_DIRECTORY=$4
    RET_SETUP_SCRIPT_NAME=$setup_file.lst
}

#---------------------------------------------------------------------------
# -- setup package's **git-master** scm directory in preparation for 
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
        print_error "No package name for git extraction. See LSST buildbot developer."
        RETVAL=1
        return 1
    fi

    if [[ "$2" != "BUILD" && "$2" != "BOOTSTRAP" ]]; then
        print_error "Failed to include legitimate purpose of directory extraction: $2. See LSST buildbot developer."
        RETVAL=1
        return 1
    fi

    local SCM_PACKAGE=$1 
    local PASS=$2

    # package is internal and should be built from git-master
    scm_url $SCM_PACKAGE
    if [[ $? != 0 ]]; then
       print_error "Failed acquiring git repository for: $SCM_PACKAGE"
       RET_REVISION=""
       REVISION=""
       SCM_URL=""
       SCM_LOCAL_DIR=""
       RETVAL=1
       return 1
    fi
    local PLAIN_VERSION="$RET_REVISION"
    RET_REVISION="$RET_REVISION"
    SCM_URL=$RET_SCM_URL
    REVISION=$RET_REVISION

    print "Internal package: $SCM_PACKAGE will be built from git-master version: $PLAIN_VERSION"
   
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
    #OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO
    # Problem with this operation is that if package doesn't exist, it returns:
    # "Initialized empty Git repository in /nfs/lsst/home/buildbot/RHEL6/gitwork/builds/TvT/work/git/LSSTPipe/.git/"
    # and returns success!   
    # URL should exist because validated when $SCM_URL is defined. 
    # However, still need to fix up following error check (an ssh timeout, etc)
    #OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO
    verbose_execute $SCM_COMMAND
    if [ $RETVAL = 1 ] ; then
       return 1
    fi

    # Set flag indicating ready for source build
    touch $SCM_LOCAL_DIR/NEEDS_BUILD
    if [ $? != 0 ]; then
        print_error "Unable to create temp file: $SCM_LOCAL_DIR/NEEDS_BUILD for prepareSCMDirectory."
        RETVAL=1
        return 1
    fi
    echo "SCM directory prepared"
    RETVAL=0
    return 0
}
