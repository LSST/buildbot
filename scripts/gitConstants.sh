#! /bin/bash

URL_BUILDERS="http://lsst-web.ncsa.illinois.edu/build/builders"

SW_SERVER="sw.lsstcorp.org/pkgs"
DEV_SERVER="sw.lsstcorp.org"
SCM_SERVER="git.lsstcorp.org"
WEB_HOST="lsst-web.ncsa.illinois.edu"

# This following is NOT a global across all scripts! 
# The name is shared by the following and /usr/local/home/buildbot/www/
WEB_ROOT="/var/www/html/doxygen"

ASTROMETRY_NET_DATA_DIR=/lsst/DC3/data/astrometry_net_data/

DEMO_ROOT="https://dev.lsstcorp.org/cgit/contrib/demos/lsst_dm_stack_demo.git/snapshot"
DEMO_TGZ="lsst_dm_stack_demo-master.tar.gz"

#LSST_DEVEL_RUNS_EMAIL="lsst-devel-runs@lsstcorp.org"

BUILDBOT_SUCCESS=0
BUILDBOT_FAILURE=1
BUILDBOT_WARNING=2
BB_ANCESTRAL_HOME="/lsst/home/buildbot"


