#==============================================================
# Set a global used for error messages to the buildbot guru
#==============================================================
BUCK_STOPS_HERE="srp@ncsa.uiuc.edu"

#--
# Library of Functions:
#    print()
#    print_error()
#    debug()
#    verbose_execute() 
#    quiet_execute()
#    pretty_execute()
#    step()
#    split()
#    copy_log()
#--

#---------------------------------------------------------------------------
# print, with an indent determined by the command line -indent option
SPACES="                                                                   "
print() {
    echo "${SPACES:0:$INDENT}$@"
}

#---------------------------------------------------------------------------
# print to stderr -  Assumes stderr is filedescriptor 2.
print_error() {
    print $@ > /proc/self/fd/2
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
    # This command '$@ | $awk_cmd' doesn't work because 
    # bash doesn't parse the "|"  properly in this context.
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
# print a numbered header
STEP=1
step() {
    echo
    print "== $STEP. $1 == [ $CHAIN ]"
    let "STEP += 1"
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

        if [ $? != 0 ]; then
            print_error "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            print_error "!!! Failed to copy $filename to $dest"
            print_error "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        else
            ssh $dest_host "chmod +r $remote_path"
            if [ $url ]; then
            # echo instead of print, because monitor class doesn't trim leading spaces
            echo "log file $file_description saved to $url/$url_suffix"
            fi
        fi
        rm /tmp/foo.$$
    fi

}

