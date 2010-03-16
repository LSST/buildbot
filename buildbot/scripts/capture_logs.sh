#! /bin/bash
# capture named log files (just cat them to stdout)

usage() {
    echo "Usage: $0 destination url_prefix <file names>"
    echo "Find files with names that match the arguments, and file them on a server."
    echo "   destination: an scp target -- username, host & directory to scp files to,"
    echo "                such as \"buildbot@master:/var/www/html/logs\""
    echo "    url_prefix: the beginning of a URL that points to the destination,"
    echo "                such as \"http://master/logs\""
    echo "    file names: names of files to find in the current dir"
}

check1() {
    if [ "$1" = "" -o "${1:0:1}" = "-" ]; then
	usage
	exit 1
    fi
}

check1 $@
DESTINATION=$1                  # buildbot@master:/var/www/html/logs
REMOTE_HOST=${DESTINATION%%\:*} # buildbot@master
REMOTE_DIR=${DESTINATION##*\:}  # /var/www/html/logs
shift
check1 $@
URL_PREFIX=$1
shift

HOST=`hostname`
DATE="`date +%Y`/`date +%m`/`date +%d`/`date +%H.%M.%S`"

while [ "$1" != "" ]; do
    echo "Capturing $1 ..."
    FIND_CMD="find . -name $1"
    FILES_TO_CAT=`$FIND_CMD`
    if [ "$FILES_TO_CAT" = "" ]; then
	echo "... none found."
    fi
    for FILE_TO_CAT in $FILES_TO_CAT; do
	FILE_TO_CAT=${FILE_TO_CAT#./*} # trim off ./
	LOCAL_DIR=${FILE_TO_CAT%/*}
	ssh $REMOTE_HOST "mkdir -p $REMOTE_DIR/$HOST/$DATE/$LOCAL_DIR"
	scp -q $FILE_TO_CAT $DESTINATION/$HOST/$DATE/$FILE_TO_CAT
	ssh $REMOTE_HOST "chmod +r $REMOTE_DIR/$HOST/$DATE/$FILE_TO_CAT"
	echo "log file $FILE_TO_CAT saved to $URL_PREFIX/$HOST/$DATE/$FILE_TO_CAT"
    done
    echo
    shift
done
