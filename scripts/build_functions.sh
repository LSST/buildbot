# set $RET_CURRENT_VERSION to current version of $1, from current.list
lookup_current_version() {
    fetch_current_line $@
    RET_CURRENT_VERSION=${CURRENT_LINE[2]}
}

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

# look up the owners of a package in http://dev.lsstcorp.org/trac/wiki/PackageOwners?format=txt
# return result as PACKAGE_OWNERS
PACKAGE_OWNERS_URL="http://dev.lsstcorp.org/trac/wiki/PackageOwners"
fetch_package_owners() {
    local url="$PACKAGE_OWNERS_URL?format=txt"
    local line=`curl -s $url | grep "package $1"`
    if [ "$line" ]; then
	local recipients=${line##package $1:}
	if [ ! "$recipients" ]; then
	    print "*** Error: could not extract owner(s) of $1 from $url"
	    print "***        found line \"$line\""
	fi
    fi
    if [ ! "$recipients" ]; then
	recipients="bbb@illinois.edu"
	print "*** Did not find owner(s) of $1 in $url"
	print "*** Expected \"package $1: owner@somewhere.edu, owner@gmail.com\""
	print "*** Sending notification to $recipients instead.\""
    fi
    PACKAGE_OWNERS=$recipients
    # PACKAGE_OWNERS="bbb@illinois.edu" # for debugging
}

# test "pick_newest_version" with something like this:
# pick_newest_version 1.3 1.3+foo 1.4.2 1.4 svn9999 svn11430 svn11430+foo 1.3.4 svn11431 1.4.1
# echo $RET_NEWEST_VERSION

# set RET_NEWEST_VERSION to the newer of the n versions passed in
pick_newest_version() {
    debug "Comparing versions: $@"
    unset RET_NEWEST_VERSION
    # loop through args and pick the newest (greatest) version according to eups
    while [ "$1" ]; do
	if [ "$RET_NEWEST_VERSION" ]; then
	    # -1 or 1
	    local ret=`python -c "import eups; print eups.Eups().version_cmp('$RET_NEWEST_VERSION', '$1')"`
	    if [ $ret == "-1" ]; then
		debug " - version $1 is newer than $RET_NEWEST_VERSION"
		RET_NEWEST_VERSION=$1
	    fi
	else # first time through the loop
	    RET_NEWEST_VERSION=$1
	fi
	shift
    done
}

# return 0 if $1 is external, 1 if not
package_is_external() {
    fetch_current_line $@
    local extra_dir=${CURRENT_LINE[3]}
    
    debug "extra_dir = $extra_dir (${extra_dir:0:8})"
    if [ "${extra_dir:0:8}" = "external" ]; then
	debug "$1 is an external package"
	return 0
    else
	debug "$1 is an internal LSST package"
	return 1
    fi
}

# $1 = raw package name (include devenv_ if present)
# $2 = version (3.1.2, svn3438)
# requires that SVN_SERVER be set already
# returns RET_SVN_URL, RET_SVN_ADDL_ARGS, RET_REVISION
svn_url() {
    if [ ! "$SVN_SERVER" ]; then
	print "ERROR: no svn server configured"
	return 1
    elif [ ! "$1" ]; then
	print "ERROR: no package specified"
	return 1
    else
	svn_server_dir $1

	if [ $2 = "trunk" -o "${VERSION:0:3}" = "svn" ]; then # trunk version: get from SVN trunk
	    RET_SVN_URL=svn+ssh://$SVN_SERVER/DMS/$RET_SVN_SERVER_DIR/trunk
	    if [ "$VERSION" != "trunk" ]; then
		RET_REVISION=${VERSION:3}
		RET_SVN_ADDL_ARGS="-r$REVISION"
	    fi
	else # tagged version: get from tagged branch
	    RET_SVN_URL=svn+ssh://$SVN_SERVER/DMS/$RET_SVN_SERVER_DIR/tags/$2
	fi

	return 0
    fi
}

# $1 = package name
# sets RET_SVN_SERVER_DIR
svn_server_dir() {
    RET_SVN_SERVER_DIR=${1//_//} # replace all _ with / to derive svn directory from package name
    if [ $1 = "scons" ]; then # special case
	SVN_SERVER_DIR="devenv/sconsUtils"
    fi
    return 0
}

# fetch $1's line from current.list, and set $CURRENT_LINE to its
# contents, as an array, split by white space
fetch_current_line() {
    debug "Look up current version of $1 in current.list"
    local current_list_url="http://$DEV_SERVER/dmspkgs/current.list"
    local active_list_url="http://$DEV_SERVER/dmspkgs/active.list"
    local line=`curl -s $current_list_url | grep "^$1 "`
    if [ $? = 1 ]; then
	print "Couldn't fetch $current_list_url:"
	pretty_execute curl $current_list_url # print error code
    fi
    if [ "$line" == "" ]; then
#	print "$1 not found in $current_list_url;"
#	print "Checking $active_list_url instead."
	local line=`curl -s $active_list_url | grep "^$1 "`
	if [ $? = 1 ]; then
	    print "Couldn't fetch $active_list_url:"
	    pretty_execute curl $active_list_url
	fi
    fi
    if [ "$line" == "" ]; then
#	print "no package '$1' listed in $current_list_url or $active_list_url"
	if [ "$SVN_SERVER" ]; then
	    print "checking svn repository instead"
	    svn_url $1 trunk
	    lookup_svn_revision $RET_SVN_URL
	    if [ $? == 0 ]; then
		# fake it with trunk version -- could use "trunk" as version instead
		line="$1 generic svn$RET_REVISION"
		#line="$1 generic trunk"
	    fi
	fi
    fi
    if [ "$line" == "" ]; then
	print "unable to look up current version of $1 in $current_list_url, $active_list_url, or svn"
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

# print a numbered header
STEP=1
step() {
    echo
    print "== $STEP. $1 == [ $CHAIN ]"
    let "STEP += 1"
}

# print, with an indent determined by the command line -indent option
SPACES="                                                                   "
print() {
    echo "${SPACES:0:$INDENT}$@"
}

# print, but only if -verbose or -debug is specified
debug() {
    if [ "$DEBUG" ]; then
	print $@
    fi
}

# execute the command; if verbose, make its output visible
verbose_execute() {
    if [ "$DEBUG" ]; then
	pretty_execute $@
    else
	quiet_execute $@
    fi
}

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
	print "*** Unable to pretty-print: $tmp_cmd, $tmp_out, or $tmp_err exists. ***"
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
	scp -q $filename $dest
    
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

svn_info() {
    local svn_dir=$1
    shift
    local cmd="svn info $svn_dir | grep -v \"Path: \" | grep -v \"UUID: \" | grep -v \"Repository Root: \" | grep -v \"Node Kind: \" | grep -v \"Schedule: \" | grep -v '^$' | awk '{print \"--- \"\$0}' | replace \"Revision: \" \"Revision: http://dev.lsstcorp.org/trac/changeset/\" | replace \"Rev: \" \"Rev: http://dev.lsstcorp.org/trac/changeset/\"$@"
    eval $cmd
}

# sets RET_REVISION to the svn version of the trunk of the specified package
lookup_svn_trunk_revision() {
    svn_url $1 trunk
    lookup_svn_revision $RET_SVN_URL
}

# sets RET_REVISION to the svn version of the current dir or url
lookup_svn_revision() {
    local line=`svn info $1 | grep "Last Changed Rev"`
    if [ $? != 0 ]; then
	print "ERROR: unable to retrieve svn info for $1"
	RET_REVISION="error"
	return 1
    else
	# revision is last word in line returned by "svn info | grep Revision"
	for RET_REVISION in $line; do true; done
	return 0
    fi
}

# update TRUNK_PACKAGE_COUNT to match the number of packages whose version matches svn#### or "trunk"
count_trunk_packages() {
    TRUNK_PACKAGE_COUNT=`eups list | grep -P "svn|trunk" | grep -v LOCAL | wc -l`
#    let TRUNK_PACKAGE_COUNT=TRUNK_PACKAGE_COUNT+`eups list | grep trunk | grep -v LOCAL | wc -l`
}

# attempt eups remove on each package whose version matches svn#### or equals "trunk"
remove_trunk_packages() {
    local word
    for word in `eups list | grep -P "svn|trunk"`; do
	if [ "${word:0:3}" = "svn" -o "$word" = "trunk" ]; then
	    local version=$word
	    local is_setup=`eups list ctrl_events $version | grep -i setup`
	    if [ $is_setup ]; then unsetup $package; fi
	    #pretty_execute "eups remove --force $package $version"
	    verbose_execute "eups undeclare --force $package $version"
	else
	    local package=$word
	fi
    done
}
