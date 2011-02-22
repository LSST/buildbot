#
# LSST Data Management System
# Copyright 2008, 2009, 2010 LSST Corporation.
#
# This product includes software developed by the
# LSST Project (http://www.lsst.org/).
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the LSST License Statement and
# the GNU General Public License along with this program.  If not,
# see <http://www.lsstcorp.org/LegalNotices/>.

######################################################################
# garbageCollectFbot.sh - deletes all buildbot residue > 7 days old. #
#                         Paths tuned for fbot.ncsa.illinois.edu     #
#                         May be used as cron script.                #
######################################################################
#####  B Y   H A N D :    fix path to WORK_DIR & to loadLSST.sh  #####
######################################################################

# Following finds all working buildbot directories older than 7 days,
# then extracts packageName and packageVersion so a compound command to both
# remove the directory and undeclare the package is fabricated for later
# execution by 'sh'. It assumes certain characteristics of the environment:
# * buildbot svn dirs in: /home/buildbot/slave/trunkVsTrunk_fbot/work/svn
# * dirs have package names w/ associated svn # appended and
# * the eups version number (which == svn#) is preceded by 'svn_'.

export WORK_DIR=/home/buildbot/slave/trunkVsTrunk_fbot/work;source /lsst/DC3/stacks/gcc443/loadLSST.sh;find $WORK_DIR -maxdepth 2 -ctime +7 | grep '/svn/'| sed -e "s|.*\/svn\/\(.*\)_\([0-9]*\)|rm -rf $WORK_DIR/svn/\1_\2 ; eups undeclare \1 svn_\2|" | sh

##############################################################################
# Before using the first time...check the script works to your satisfaction:
##############################################################################
#  Swap the 'rm -rf' with 'ls -ld' & remove 'eups undeclare' clause; then run.
#  Now: check that the dates are > 7 days.
#export WORK_DIR=/home/buildbot/slave/trunkVsTrunk_fbot/work;source /lsst/DC3/stacks/gcc443/loadLSST.sh;find $WORK_DIR -maxdepth 2 -ctime +7 | grep '/svn/'| sed -e "s|.*\/svn\/\(.*\)_\([0-9]*\)|ls -ld $WORK_DIR/svn/\1_\2|" | sh

# Finally: check each package has version younger than 7 days old.
#ls -ld /home/buildbot/slave/trunkVsTrunk_fbot/work/svn/*

