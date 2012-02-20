#!/usr/bin/python

###
# bootstrap.py - output all the package names and current trunk git 
#                hash tags for packages listed in the distribution server's
#                current.list URL
#
import os
##
# exclude these packages  - for packages which have been abandoned
#                           or are just lsstpkg aliases
#
exclude_pkgs=set(["lsst","lssteups","sconsUtils","LSSTPipe", "lsstactive", "thirdparty_core", "obs_cfht", "ip_pipeline", "meas_pipeline", "coadd_pipeline", "meas_multifit", "ip_diffim" ])

##
# current_list is the URL of the distribution stack contents
#
current_list = "http://dev.lsstcorp.org/pkgs/std/w12/current.list"

##
# createGitURL(package) - create the Git URL for a given package
#
def createGitURL(package):
	return "git@git.lsstcorp.org:LSST/DMS/"+package+".git"

##
# open a the current.list URL, and remove the first line, and any lines
# containing "pseudo", "external", or that start with a comment character
#
stream = os.popen("curl -s "+current_list+"| grep -v pseudo| grep -v external |  grep -v EUPS| awk '{print $1 ;}' | grep -v ^#")

##
# read all the packages of the stream, and put them into a set, removing
# the excluded packages.
#
pkgs = stream.read()
pkg_list = set(pkgs.split())-exclude_pkgs

##
# open each of the packages at the distribution stack URL, look up the hash
# tag for the trunk, and output the package name and hash take to STDOUT
#
for pkg in pkg_list:
    gitURL = createGitURL(pkg)
    try:
        stream=os.popen("git ls-remote --refs -h "+ gitURL +" | grep refs/heads/master | awk '{print $1}'")
        hashTag = stream.read()
        print pkg+" "+hashTag.strip()
    except IOError:
        pass
