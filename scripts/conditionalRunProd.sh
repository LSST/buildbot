#!/bin/bash

# this is a wrapper script to call the script which executes a  production run. 
# This is meant to be run from  the builds/work directory.

# arguments
# --package : package we're looking at to see if dependencies are built
# --script_dir : location of the buildbot scripts. used to invoke other scripts
# --doxygen_dest : passed to the create_xlinkdocs.sh script
# --doxygen_url : passed to the create_xlinkdocs.sh script
# --manifest : full manifest of successfully built datarel & testing_endtoend
DEBUG=""
PACKAGE=""
SCRIPT_DIR=""
PACKAGE="datarel"
BUILDER_NAME=""
BUILD_NUMBER=""
MANIFEST=""

#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\
#                   NOTE feature creep option
# If MANIFEST is acquired from the user via web-form, they could initiate
# a production run using this script as a basis for new buildslave.  
#/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\

##
# get the arguments
##
options=$(getopt -l debug,builder_name:,build_number:,script_dir:,ccd_count:,astro_net_data:,input_data:,manifest: -- "$@")

while true
do
        case $1 in
            --debug) DEBUG=1; shift 1;;
            --script_dir) SCRIPT_DIR=$2; shift 2;;
            --builder_name) BUILDER_NAME=$2; shift 2;;
            --build_number) BUILD_NUMBER=$2; shift 2;;
            --manifest) MANIFEST=$2; shift 2;;
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
if [ "$SCRIPT_DIR" == "" ] || [ "$BUILDER_NAME" == "" ] || [ "$BUILD_NUMBER" == "" ] || [ "$CCD_COUNT" == "" ] || [ "$ASTRO_DATA" == "" ] || [ "$MANIFEST" == "" ]; then
    echo "usage: $0 --script_dir <buildbot script dir> --builder_name <name> --build_number <#> --ccd_count <#>  --astro_net_data <eups version> --input_data <input dataset>"
    exit 1
fi

if [ ! -f $MANIFEST ] ; then
    echo "Manifest: $MANIFEST, not found."
    exit 1
fi

$SCRIPT_DIR/runManifestProduction.sh  --ccdCount $CCD_COUNT --runType buildbot --astro_net_data $ASTRO_DATA --input_data $INPUT_DATA --builder_name "$BUILDER_NAME" --build_number $BUILD_NUMBER  --manifest $MANIFEST --beta

