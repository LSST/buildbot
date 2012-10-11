#==============================================================
# Set a global used for error messages to the buildbot guru
#==============================================================
BUCK_STOPS_HERE="robyn@LSST.org"

# See fetch_blame_data
STEP_BLAMEFILE="buildbot_tVt_blame"    # see fetch_blame_data

# --
# Library Functions which relate to the Source Configuration Manager (SCM)
# -----------------
# scons_tests() 
# fetch_package_owners() 
# clear_blame_data() 
# fetch_blame_data() 
# package_is_external()
# package_is_special()
# scm_url_to_package() 
# scm_url() 
# scm_server_dir() 
# fetch_current_line() 
# pretty_execute2() 
# scm_info() 
# saveSetupScript()
# prepareSCMDirectory()  - this is only used by stack build slaves
# clonePackageMasterRepository()  - this is only used for 'master' repo fetch
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
    unset STEP_FAILURE_BLAME
}

#---------------------------------------------------------------------------
# $1 = git directory of package version which failed build.
# $2 - directory where a temp file can be stashed
# return result as RET_BLAME_EMAIL
fetch_blame_data() {
    local BLAME_PWD=`pwd`
    STEP_FAILURE_BLAME="$2/$STEP_BLAMEFILE"
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
    touch  $STEP_FAILURE_BLAME
    if [ $? != 0 ]; then
        print "Unable to create temp file: $STEP_FAILURE_BLAME for blame details."
        STEP_FAILURE_BLAME="/dev/null"
    fi
    git log --name-status --source -1 > $STEP_FAILURE_BLAME
    cat $STEP_FAILURE_BLAME >> $WORK_PWD/$BUILD_FAILURE_BLAME
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
    elif [ "${extra_dir:0:8}" = "pseudo" ]; then
        debug "$1 is an pseudo package"
        return 0
    fi
return 1
}

#--------------------------------------------------------------------------
# -- Some LSST internal packages should never be built from master --
# $1 = eups package name
# return 0 if a special LSST package which should be considered external
# return 1 if package should be processed as usual
package_is_special() {
    if [ "$1" = "" ]; then
        print_error "============================================================="
        print_error "No package name provided for package_is_special check. See LSST buildbot developer."
        print_error "============================================================="
        exit $BUILDBOT_FAILURE
    fi
    local SPCL_PACKAGE="$1"

    # 23 Nov 2011 installed toolchain since it's not in active.list, 
    #             required by tcltk but not an lsstpkg distrib package.
    # 27 Jan 2012 added obs_cfht (bit rot)
    # 13 Feb 2012 added *_pipeline (old)
    # 16 Feb 2012 added meas_multifit (old)
    # 24 May 2012 added obs_subaru bypass
    # 4 June 2012 added sdqa (old)
    # 4 June 2012 added afw_extensions_rgb analysis meas_deblender (too new)
    # 6 Sep  2012 added obs_sst - never to be DM used accding Paul Price
    # 21 Sep 2012 added ctrl_execute, ctrl_platform_lsst, ctrl_platform_gordon
    #                   as too new per SRP
    # 10 Oct 2012 added obs_decam & scipy

#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\
# N O T E: 
# If you change this, remember to change: buildmaster/templates/layout.html
#                                and possibly, RHEL6/etc/excluded*.txt
#\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
##        -o ${SPCL_PACKAGE:0:16}  = "meas_extensions_"  
# Not all are git $LSST_DMS/<package>.git
    if [ "$CC" = "clang" -a \
        \( ${SPCL_PACKAGE}            = "ctrl_events"  \
        -o  ${SPCL_PACKAGE}         = "ctrl_sched"  \
        -o  ${SPCL_PACKAGE}         = "ctrl_orca"  \
        -o  ${SPCL_PACKAGE}         = "pex_harness"  \
        -o  ${SPCL_PACKAGE}         = "testing_endtoend"  \
        -o  ${SPCL_PACKAGE}         = "datarel"  \) \
        ]; then
        return 0
    fi

    if [ ${SPCL_PACKAGE}         = "coadd_pipeline"  \
        -o ${SPCL_PACKAGE}       = "obs_decam"  \
        -o ${SPCL_PACKAGE}       = "scipy"  \
        -o ${SPCL_PACKAGE}       = "ctrl_execute"  \
        -o ${SPCL_PACKAGE}       = "ctrl_platform_lsst"  \
        -o ${SPCL_PACKAGE}       = "ctrl_platform_gordon"  \
        -o ${SPCL_PACKAGE}       = "afw_extensions_rgb"  \
        -o ${SPCL_PACKAGE}       = "analysis"  \
        -o ${SPCL_PACKAGE}       = "meas_deblender"  \
        -o ${SPCL_PACKAGE}       = "ip_pipeline"  \
        -o ${SPCL_PACKAGE}       = "meas_multifit"  \
        -o ${SPCL_PACKAGE}       = "meas_pipeline"  \
        -o ${SPCL_PACKAGE:0:5}   = "mops_"  \
        -o ${SPCL_PACKAGE}       = "obs_cfht"  \
        -o ${SPCL_PACKAGE}       = "obs_subaru"  \
        -o ${SPCL_PACKAGE}       = "obs_sst"  \
        -o ${SPCL_PACKAGE}       = "sdqa"  \
        -o ${SPCL_PACKAGE}       = "auton"  \
        -o ${SPCL_PACKAGE:0:6}   = "condor"  \
        -o ${SPCL_PACKAGE:0:7}   = "devenv_"  \
        -o ${SPCL_PACKAGE}       = "gcc"  \
        -o ${SPCL_PACKAGE}       = "mpfr"  \
        -o ${SPCL_PACKAGE}       = "sconsUtils" \
        -o ${SPCL_PACKAGE}       = "ssd"  \
        -o ${SPCL_PACKAGE}       = "toolchain" \
        -o ${SPCL_PACKAGE}       = "afwdata" \
        -o ${SPCL_PACKAGE}       = "astrometry_net_data" \
        -o ${SPCL_PACKAGE}       = "coadd_pipeline_data"  \
        -o ${SPCL_PACKAGE}       = "isrdata"  \
        -o ${SPCL_PACKAGE}       = "meas_algorithmdata"  \
        -o ${SPCL_PACKAGE}       = "multifit"  \
        -o ${SPCL_PACKAGE}       = "simdata"  \
        -o ${SPCL_PACKAGE}       = "subaru"  \
        -o ${SPCL_PACKAGE}       = "testdata_subaru"  \
        ]; then
        return 0
    fi
    return 1
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
local POSSIBLE=`echo $1 | sed -e "s/^\(.*:\)\{0,1\}LSST\/DMS\/\(.*\).git$/\2/"`
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
# $2 = git-branch if package does NOT have specified git-branch, 
#                 then master branch is used.
# requires SCM_SERVER be set already
#          <work>/manifest.list  exist
# returns RET_SCM_URL, RET_REVISION
scm_url() {
    if [ ! "$SCM_SERVER" ]; then
        print_error "ERROR: no SCM server configured"
        return 1
    elif [ ! "$1" ]; then
	    print_error "ERROR: no package specified"
        return 1
    elif [ ! "$2" ]; then
	    print_error "ERROR: no git-branch specified"
        return 1
    fi

    # removed in the great git repository rename of 2011
    #scm_server_dir $1

    RET_SCM_URL=git@$SCM_SERVER:LSST/DMS/$1.git
    # Verify URL addresses a real git repo.
    git ls-remote $RET_SCM_URL > /dev/null
    if [ $? != 0 ]; then
        print_error "Failed to find a git repository matching URL: $RET_SCM_URL"
        return 1
    fi

    # Will now acquire the gitId picked up from the manifest.list
    if [ ! -e manifest.list ]; then
        print_error "Required file: <work>/manifest.list does not exist.\nIs current buildslave step occurring before 'getVersions' step?"
        return 1
    fi
    RET_REVISION=`grep -w $1 manifest.list | awk '{print $2}'`
    if [ "RET_REVISION" = "" ]; then
        print_error "Failed getting either git refs/heads/{$2 or master} commit id for package $1." 
        return 1 
fi

}

#---------------------------------------------------------------------------
#    O B S O L E T E - why is it still here?  because we may need to use it
#                      on the devenv/* packages with non-standard git names
# $1 = package name
# sets RET_SCM_SERVER_DIR
scm_server_dir() {
    RET_SCM_SERVER_DIR=${1//_//} # replace all _ with / to derive directory from package name
    if [ $1 = "scons" ]; then # special case
	RET_SCM_SERVER_DIR="devenv/sconsUtils"
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
#
#    NOTE:        this is only used by stack build slaves
#
# -- setup package's **git-master** scm directory in preparation for 
#        either extracting initial source tree to bootstrap dependency tree 
#        or the build  and install the accurate deduced dependency tree
# $1 = adjusted eups package name
# $2 = git-branch from which to extract package
# $3 = purpose of directory; one of: 
#         "BOOTSTRAP" :extracted directory only to be used for dependency tree
#         "BUILD" : extracted directory to be used for build
# return:  0, if svn checkout/update occured withuot error; 1, otherwise.
#       :  RET_REVISION
#       :  SCM_URL
#       :  REVISION 
#       :  SCM_PKG_VER_DIR

prepareSCMDirectory() {

    # ------------------------------------------------------------
    # -- NOTE:  most variables in this function are global!  NOTE--
    # ------------------------------------------------------------

    if [ "$1" = "" ]; then
        print_error "No package name for git extraction. See LSST buildbot developer."
        RETVAL=1
        return 1
    fi

    if [ "$2" = "" ]; then
        print_error "No git-branch name for git extraction. See LSST buildbot developer."
        RETVAL=1
        return 1
    fi

    if [[ "$3" != "BUILD" && "$3" != "BOOTSTRAP" ]]; then
        print_error "Failed to include legitimate purpose of directory extraction: $3. See LSST buildbot developer."
        RETVAL=1
        return 1
    fi

    local SCM_PACKAGE=$1 
    local GIT_BRANCH=$2
    local PASS=$3
    print "SCM_PACKAGE: $SCM_PACKAGE  GIT_BRANCH: $GIT_BRANCH  PASS: $PASS"

    # package is internal and should be built from git-source
    scm_url $SCM_PACKAGE  $GIT_BRANCH
    if [[ $? != 0 ]]; then
       print_error "Failed finding git repository for package: $SCM_PACKAGE"
       RET_REVISION=""
       REVISION=""
       SCM_URL=""
       SCM_PKG_VER_DIR=""
       RETVAL=1
       return 1
    fi
    local PLAIN_VERSION="$RET_REVISION"
    RET_REVISION="$RET_REVISION"
    SCM_URL=$RET_SCM_URL
    REVISION=$RET_REVISION
    local WORK_DIR=$PWD
    print "Internal package: $SCM_PACKAGE will be built from git-id: $PLAIN_VERSION"
    print "Working directory is $WORK_DIR" 

    mkdir -p git
    SCM_PKG_DIR="git/${SCM_PACKAGE}"
    SCM_PKG_VER_DIR="$SCM_PKG_DIR/${PLAIN_VERSION}"
    
    if [ -e $SCM_PKG_VER_DIR ] ; then
        cd $SCM_PKG_VER_DIR
        # To guard against:  existing branch != requested branch -> NEEDS_BUILD
        print "Local directory: $SCM_PKG_VER_DIR exists, ensure correct branch: $BRANCH"
        git checkout $GIT_BRANCH 1> clone.stdout 2> clone.stderr
        if [ $? != 0 ] ; then
            print_error "WARNING: $SCM_PACKAGE does not have branch: $GIT_BRANCH, trying 'master'"
            git checkout master 1> clone.stdout 2> clone.stderr
            if [ $? != 0 ] ; then
                print_error "FAILURE: ==============================="
                print_error "FAILURE: Failed to change existing git directory branch to either $GIT_BRANCH or 'master'"
                print_error "FAILURE: stderr:"
                cat clone.stderr
                print_error "FAILURE: ==============================="
                rm -f clone.stdout clone.stderr
                cd $WORK_DIR
                RETVAL=1
                return $RETVAL
            else
                print_error "WARNING: $SCM_PACKAGE does not have branch: $GIT_BRANCH, using branch: master, instead."
            fi
        # git checkout of branch ok, now check if new use of that branch,
        #     if so, then -> set NEEDS_BUILD and remove BUILD_OK
        #     if existing use of directory, no change in flag status
        elif [ "`cat clone.stderr | head -1 | awk '{ print $1 }'`" = "Switched" ]; then
            touch $SCM_PKG_VER_DIR/NEEDS_BUILD
            rm -f $SCM_PKG_VER_DIR/BUILD_OK
        fi

        cd $WORK_DIR
        print "Local directory: $SCM_PKG_VER_DIR exists, checking PASS: $PASS"
        if [ $PASS != "BUILD" ] ; then
            # Just need source directory to generate the dependency list so 
            # no need to clear build residue
            print "PASS!= BUILD so Dir only needed to generate the dependency list; no need to clear build residue."
            RETVAL=0
            return 0
        elif [ $PASS = "BUILD" ] ; then
            print "PASS=BUILD; now check if still NEEDS_BUILD."
            # Need source directory for build; now check its status
            if [ -f $SCM_PKG_VER_DIR/NEEDS_BUILD ] ; then
                print "PASS=BUILD, NEEDS_BUILD, too; ready to build dir now."
                RETVAL=0
                return 0
            # Following should not be needed since this routine shouldn't be
            #   called if BUILD_OK exists in build dir.
            elif [ -f $SCM_PKG_VER_DIR/BUILD_OK ] ; then
                print "PASS=BUILD, BUILD_OK so no need to rebuild."
                RETVAL=0
                return 0
            else # Danger: previous build failed, remove dir and re-extract
                print "PASS=BUILD but no BUILD_OK so must remove suspect build directory."
                if [ `eups list $SCM_PACKAGE $REVISION | grep -i setup | wc -l` = 1 ]; then
                    unsetup -j $SCM_PACKAGE $REVISION
                fi
                pretty_execute "eups remove -N $SCM_PACKAGE $REVISION"
                pretty_execute "rm -rf $SCM_PKG_VER_DIR"
            fi
        fi
    fi

    # Now extract fresh source directory
    mkdir -p $SCM_PKG_VER_DIR
    step "Check out $SCM_PACKAGE $REVISION from $SCM_URL"

    git clone $SCM_URL $SCM_PKG_VER_DIR 1> clone.stdout 2> clone.stderr
    RETVAL=$?
    if [ ! -e $SCM_PKG_VER_DIR/.git ]; then
        print_error "FAILURE: ==============================="
        print_error "FAILURE: to find $SCM_PKG_VER_DIR/.git. Was there an ssh timeout?"
        print_error "FAILURE: stderr:"
        cat clone.stderr
        print_error "FAILURE: ==============================="
        RETVAL=1
        rm -f clone.stdout clone.stderr
        return $RETVAL
    elif [ $RETVAL != 0 ] ; then
        print_error "FAILURE: ==============================="
        print_error "FAILURE: Well something went wrong, what does the error file say?"
        print_error "FAILURE: stdout:"
        cat clone.stdout
        print_error "FAILURE: ==============================="
        print_error "FAILURE: stderr:"
        cat clone.stderr
        print_error "FAILURE: ==============================="
        rm -f clone.stdout clone.stderr
        return $RETVAL
    fi
    cd $SCM_PKG_VER_DIR
    #switch to desired git-branch; first try $GIT_BRANCH then 'master'
    git checkout $GIT_BRANCH 1> clone.stdout 2> clone.stderr
    if [ $? != 0 ] ; then
        print_error "WARNING: $SCM_PACKAGE does not have branch: $GIT_BRANCH, trying branch: master."
        git checkout master 1> clone.stdout 2> clone.stderr
        if [ $? != 0 ] ; then
            print_error "FAILURE: ==============================="
            print_error "FAILURE: Failed to change current git branch to either $GIT_BRANCH or 'master'"
            print_error "FAILURE: stderr:"
            cat clone.stderr
            print_error "FAILURE: ==============================="
            rm -f clone.stdout clone.stderr
            RETVAL=1
            return $RETVAL
        else
            print_error "WARNING: $SCM_PACKAGE does not have branch: $GIT_BRANCH, using branch: master, instead."
        fi
    fi
    cat clone.stdout
    rm -f clone.stdout clone.stderr
    cd $WORK_DIR

    # Set flag indicating ready for source build
    touch $SCM_PKG_VER_DIR/NEEDS_BUILD
    if [ $? != 0 ]; then
        print_error "Unable to create temp file: $SCM_PKG_VER_DIR/NEEDS_BUILD for prepareSCMDirectory."
        RETVAL=1
        return 1
    fi
    echo "SCM directory prepared"
    RETVAL=0
    return 0
}



#---------------------------------------------------------------------------
#
#   NOTE: this is only used for a package's 'master' repo fetch
#
# Input: 
#     1: git repo name; e.g. afw.git
#     2: local directory name in which to load extracted package
# Required: 
#     LSST_DMS   
# Return:
clonePackageMasterRepository() {
    # extract SCM clone ** from master **
    if [ "X$1" = "X" ]; then
        echo "Missing all arguments to clonePackageMasterRepository()."
        return 1
    fi
    PACKAGE=$1

    if [ "X$2" = "X" ]; then
        echo "Missing output directory name in clonePackageMasterRepository()."
        return 1
    fi
    LOCAL_DIR=$2

    if [ "X$LSST_DMS" = "X" ]; then
        echo "Missing LSST_DMS git web address in clonePackageMasterRepository()."
        return 1
    fi

    echo "Package: $PACKAGE LocalDirectory: $LOCAL_DIR"

    git clone $LSST_DMS/$PACKAGE --depth=1 $LOCAL_DIR
    if [ "$?" != "0" ]; then
        echo "Failed to clone $LSST_DMS/$PACKAGE . "
        return 1
    fi
}

