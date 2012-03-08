#!/usr/bin/python

###
# bootstrap.py - output all the package names and current master git 
#                hash tags for packages
#
import os

class PackageList:

    def __init__(self,**kwargs):
        ##
        # current_list is the URL of the manifest for all git repositories.
        #
        current_list = "http://dev.lsstcorp.org/cgi-bin/build/repolist.cgi"
        
        ##
        # # F Y I:
        # # Following is content of cgi script accessed in 'current_list':
        # REPODIR=/lsst_ibrix/gitolite/repositories/LSST/DMS
        # echo "Content-type: text/html"
        # echo
        # /bin/ls -d $REPODIR/*git | sed 's/\/lsst_ibrix\/gitolite\/repositories\/LSST\/DMS\///'
        # # Problem is '$REPODIR/*git'  excludes all the git-packages 
        # # which are more than one level from  LSST/DMS.


        
        #
        stream = os.popen("curl -s "+current_list)
        
        ##
        # read all the packages of the stream, and put them into a set, removing
        # the excluded packages.
        #
        
        pkgs = stream.read().split()
        stream.close()

        
        # read in a list of packages we know are excluded.
        excluded_internal_list = "/lsst/home/buildbot/RHEL6/etc/excluded.txt"
        stream = open(excluded_internal_list,"r")
        excluded_internal_pkgs = stream.read().split()
        stream.close()

        self.pkg_list = []
        for name in pkgs:
            if (name in excluded_internal_pkgs) == False:
                index = name.rfind(".git")
                self.pkg_list.append(name[:index])
        
        
    def getPackageList(self):
        return self.pkg_list

p = PackageList()
ps = p.getPackageList()
for pkg in ps:
    gitURL = "git@git.lsstcorp.org:LSST/DMS/"+pkg+".git"
    try:
        stream=os.popen("git ls-remote --refs -h "+ gitURL +" | grep refs/heads/master | awk '{print $1}'")
        hashTag = stream.read()
        print pkg+" "+hashTag.strip()
    except IOError:
        pass
