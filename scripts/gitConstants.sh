#! /bin/bash

URL_BUILDERS="http://lsst-web.ncsa.illinois.edu/build/builders"
#URL_BUILDERS="http://lsst-build4.ncsa.illinois.edu:8010/builders"
#URL_BUILDERS="http://lsst-build4.ncsa.illinois.edu:8020/builders"
LSST_STACK=$LSST_HOME

SW_SERVER="sw.lsstcorp.org"
DEV_SERVER="sw.lsstcorp.org"
SCM_SERVER="git.lsstcorp.org"
WEB_HOST="lsst-web.ncsa.illinois.edu"
WEB_ROOT="/var/www/html/doxygen"

MANIFEST_LISTS_ROOT_URL="http://$SW_SERVER"
CURRENT_PACKAGE_LIST_URL="$MANIFEST_LISTS_ROOT_URL/beta.list"

DRP_LOCK_PATH="/lsst3/weekly/datarel-runs/locks"
MAX_DRP_LOCKS=3

LSST_DEVEL_RUNS_EMAIL="lsst-devel-runs@lsstcorp.org"

BUILDBOT_SUCCESS=0
BUILDBOT_FAILURE=1
BUILDBOT_WARNINGS=2

