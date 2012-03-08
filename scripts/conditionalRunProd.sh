#!/bin/bash

# this script checks to see all the dependencies for a given package are
# marked with a BUILD_OK, and if they are, will execute a 
# production run. This is meant to be run from the builds/work directory.

# arguments
# --package : package we're looking at to see if dependencies are built
# --script_dir : location of the buildbot scripts. used to invoke other scripts
# --doxygen_dest : passed to the create_xlinkdocs.sh script
# --doxygen_url : passed to the create_xlinkdocs.sh script
DEBUG=""
PACKAGE=""
SCRIPT_DIR=""
PACKAGE="datarel"
BUILDER_NAME=""
BUILD_NUMBER=""

#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\
#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\
#                   NOTE feature creep option
# If MANIFEST is acquired from the user via web-form, they could initiate
# a production run using this script as a basis for new buildslave.  

LAST_SUCCESSFUL_MANIFEST="lastSuccessfulBuildManifest.list"

#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\
#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\

##
# get the arguments
##
options=$(getopt -l debug,builder_name:,build_number:,script_dir:,ccd_count:,astro_net_data:,input_data: -- "$@")

while true
do
        case $1 in
            --debug) DEBUG=1; shift 1;;
            --script_dir) SCRIPT_DIR=$2; shift 2;;
            --builder_name) BUILDER_NAME=$2; shift 2;;
            --build_number) BUILD_NUMBER=$2; shift 2;;
            --ccd_count) CCD_COUNT=$2; shift 2;;
            --astro_net_data) ASTRO_DATA=$2; shift 2;;
            --input_data) INPUT_DATA=$2; shift 2;;
            *) echo "parsed options; arguments left are: $*"
                break;;
        esac
done

##
# sanity check to be sure we got all the arguments
##
if [ "$SCRIPT_DIR" == "" ] || [ "$BUILDER_NAME" == "" ] || [ "$BUILD_NUMBER" == "" ] || [ "$CCD_COUNT" == "" ] || [ "$ASTRO_DATA" == "" ]; then
    echo "usage: $0 --script_dir <buildbot script dir> --builder_name <name> --build_number <#> --ccd_count <#>  --astro_net_data <eups version> --input_data <input dataset>"
    exit 1
fi

##
# grab the version of $PACKAGE (i.e. datarel) from the manifest.list file
##
VERSION=`grep -w $PACKAGE manifest.list | awk '{ print $2 }'`

if [ "$DEBUG" != "" ]; then
    echo ls git/$PACKAGE/$VERSION
fi


##
# specify the internal dependencies file we're going to use to look up
# the packages that should all be built properly.
##
INTERNAL=git/$PACKAGE/$VERSION/internal.deps
if [ ! -f "$INTERNAL" ]; then
    echo "error: Can't find $INTERNAL. Exiting."
    exit 1
fi

DO_NOT_CONTINUE=0
while read LINE; do
    set $LINE
    if [ "$DEBUG" != "" ]; then
        echo setup $2 $3
        echo "Declare $2 $3"
        echo "checking git/$2/$3/BUILD_OK"
    fi
    if [ ! -f "git/$2/$3/BUILD_OK" ]; then
        echo "error: Package $2 $3 not built."
        DO_NOT_CONTINUE=1
    fi
done < $INTERNAL

if [ "$DO_NOT_CONTINUE" != "0" ]; then
    echo "Can not continue.  Exiting."
    exit 1
fi


$SCRIPT_DIR/runManifestProduction.sh  --ccdCount $CCD_COUNT --runType buildbot --astro_net_data $ASTRO_DATA --input_data $INPUT_DATA --builder_name "$BUILDER_NAME" --build_number $BUILD_NUMBER  --manifest $LAST_SUCCESSFUL_MANIFEST --beta

