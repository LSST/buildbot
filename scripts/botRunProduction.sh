#!/bin/bash

# this script checks to see all the dependencies for a given package are
# marked with a BUILD_OK, and if they are, will execute a 
# production run. This is meant to be run from the builds/work directory.

# arguments
# --manifest : full manifest of successfully built datarel & testing_endtoend
# --ccd_count : number of CCDs to process
# --astro_net_data : version of the astrometry_net_data to use
# --input_data : location of run input data directory
# --debug : includes additional debug logging
# --builder_name : name of this buildbot build e.g. Trunk_vs_Trunk
# --build_number : number assigned to this particular build

source ${0%/*}/gitConstants.sh

DEBUG=""
BUILDER_NAME=""
BUILD_NUMBER=""
MANIFEST=""
INPUT_DATA=""

#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\
#                   NOTE feature creep option
# If MANIFEST is acquired from the user via web-form, they could initiate
# a production run using this script as a basis for new buildslave.  
#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\

##
# get the arguments
##
options=$(getopt -l debug,builder_name:,build_number:,ccd_count:,astro_net_data:,input_data:,manifest: -- "$@")

while true
do
        case $1 in
            --debug) DEBUG=1; shift 1;;
            --builder_name) BUILDER_NAME=$2; shift 2;;
            --build_number) BUILD_NUMBER=$2; shift 2;;
            --manifest) MANIFEST=$2; shift 2;;
            --ccd_count) CCD_COUNT=$2; shift 2;;
            --astro_net_data) ASTRO_DATA=$2; shift 2;;
            --input_data) INPUT_DATA=$2; shift 2;;
            *) [ "$*" != "" ] && echo "parsed options; arguments left are:$*:"
                break;;
        esac
done

##
# sanity check to be sure we got all the arguments
##
if [ "$INPUT_DATA" == "" ] || [ "$CCD_COUNT" == "" ] || [ "$ASTRO_DATA" == "" ] || [ "$MANIFEST" == "" ]; then
    echo "usage: $0 [--debug]  [--builder_name <name>] [--build_number <#>] --ccd_count <#>  --astro_net_data <eups version> --input_data <input dataset>"
    exit $BUILDBOT_FAILURE
fi

if [ ! -e $MANIFEST ] || [ "`cat $MANIFEST | wc -l`" = "0" ]; then
    echo "Failed to find file: $MANIFEST, in buildbot work directory."
    exit $BUILDBOT_FAILURE
fi

echo "${0%/*}/runManifestProduction.sh  --debug --ccdCount $CCD_COUNT --runType buildbot --astro_net_data $ASTRO_DATA --input_data $INPUT_DATA --builder_name \"$BUILDER_NAME\" --build_number $BUILD_NUMBER  --manifest $MANIFEST --beta"
${0%/*}/runManifestProduction.sh --debug  --ccdCount $CCD_COUNT --runType buildbot --astro_net_data $ASTRO_DATA --input_data $INPUT_DATA --builder_name "$BUILDER_NAME" --build_number $BUILD_NUMBER  --manifest $MANIFEST --beta
STATUS=$?

# Note status return from a BUILDBOT_{SUCCESS FAILURE WARNINGS} enabled script
exit $STATUS
