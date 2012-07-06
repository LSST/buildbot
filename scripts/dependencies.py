#!/usr/bin/env python
import subprocess
import sys
import eups.Eups
import operator
import os,string

# Select the extent of the debug messages: 'True' provides more output.
#DEBUG = True
DEBUG = False

class PackageDependency:

    def gather(self,myeups,pkg,ver,depth,tags):
        #print "-"*depth,"CALLED: %s,%s depth = %d" % (pkg,ver,depth)
    
        if pkg is "implicitProducts":
            return

        prod = myeups.findSetupProduct(pkg)
        if not prod:
            print "%s is not setup, maybe it's a new external" % (pkg)
            try:
                prod = myeups.getProduct(pkg,ver)
            except:
                print "FAILURE: %s %s is not found in any stack" % (pkg,ver)
                return
            
        tbl = prod.getTable()
        myeups.selectVRO(tags)
        dependencies = tbl.dependencies(myeups,recursionDepth=1)
        for dep in dependencies:
            package = dep[0].name
            version = dep[0].version
            if DEBUG:
                print "Root: %s  %s    Dep: %s  %s" %(pkg,ver,package,version)
            #if version == None:
            #    continue
            if package not in self.externals:
                if package in self.global_pkgs:
                    if depth > self.global_pkgs[package]:
                        self.global_pkgs[package] = depth
                else:
                    self.global_pkgs[package] = depth
                self.gather(myeups,package,version,depth+1,tags)
            else:
                # package is external
                if DEBUG:
                    print "EXTERNAL PACKAGE: root: %s  %s   Dep: %s  %s" %(pkg,ver,package,version)
                self.externals[package] = version
        return

    def getDependencyList(self, package, version, tags):

        self.global_pkgs = {}

        self.global_pkgs[package] = 1
        
        myeups = eups.Eups()
        
        self.gather(myeups, package, version, 2, tags)
        
        self.sorted_pkgs = sorted(self.global_pkgs.iteritems(), key=operator.itemgetter(1), reverse=True)

        return self.sorted_pkgs
        

    def __init__(self):
        self.externals = {}
        self.global_pkgs = {}

        for name in os.listdir("/lsst/DC3/stacks/gcc445-RH6/28nov2011/Linux64/external"):
            self.externals[name] = "unknown"

class sp:

    def __init__(self):
        self.manifest = {}
        self.package_info = {}

    def readFileIntoList(self, filename):
        list = {}
        input = open(filename,"r")
        line = input.readline()
        while line:
            tokens = line.split()
            list[tokens[0]] = tokens[1]
            line = input.readline()
        return list

    def createDependencyLists(self, tags):
        self.manifest = self.readFileIntoList("manifest.list")
        print "self.manifest is ",self.manifest
        for pkg in self.manifest:
            name = pkg
            version = self.manifest[name]
            p = PackageDependency()
            list = p.getDependencyList(name,version, tags)
            print "name = ",name
            for i in list:
                print i
            print "++++"
            self.package_info[name] = list
            print "Writing dependency lists for "+name+" "+version
            f = open("git/"+name+"/"+version+"/internal.deps","w")
            for info in list:
                if info[0] in self.manifest:
                    print "internal "+info[0],self.manifest[info[0]]
                    f.write("%d %s %s\n" % (info[1], info[0],self.manifest[info[0]]))
                else:
                    print "unknown internal "+info[0]
            f.close()
            f = open("git/"+name+"/"+version+"/external.deps","w")
            for info in p.externals:
                if p.externals[info] is not "unknown":
                        print "external "+info,p.externals[info]
                        f.write("%s %s\n" % (info, p.externals[info]))
            f.close()
        return True

    def checkDependency(self, name, depList):
        for depElement in depList:
            depName = depElement[0]
            if depName == name:
                return True
        else:
            return False

    def createNeedsBuildList(self):
        
        needsToBeBuilt = []
        package_dependencies = {}
        for name in self.manifest:
            version = self.manifest[name]
            list = self.package_info[name]
            package_dependencies[name] = list
       
            if os.path.isfile("git/"+name+"/"+version+"/NEEDS_BUILD") is True:
                needsToBeBuilt.append([name,version])
        
        final_needs = {}
        if len(needsToBeBuilt) == 0:
            return None
        need_to_build_pkg = needsToBeBuilt[0]
        need_to_build_name = need_to_build_pkg[0]
        while need_to_build_pkg in needsToBeBuilt:
            needsToBeBuilt.remove(need_to_build_pkg)
            if (need_to_build_name in final_needs) == False:
                final_needs[need_to_build_name] = self.manifest[need_to_build_name]
            for pkg in self.manifest:
                if pkg != need_to_build_name:
                    if self.checkDependency(need_to_build_name,package_dependencies[pkg]):
                        if (pkg in final_needs) == False:
                            final_needs[pkg] = self.manifest[pkg]

            if len(needsToBeBuilt) > 0:
                need_to_build_pkg = needsToBeBuilt[0]
                need_to_build_name = need_to_build_pkg[0]
        
        return final_needs


p = sp()
print "Command line: ",sys.argv
if p.createDependencyLists(sys.argv[1:]) is False:
    print "error creating dependency lists"
else:
    list = p.createNeedsBuildList()

    print "these need to be built"
    print list
    if not list:
            print "Nothing needs to be built."
            sys.exit(0)
    for name in list:
            print name+" "+list[name]

    for name in list:
            version = list[name]
            if os.path.isfile("git/"+name+"/"+version+"/BUILD_OK"):
                os.unlink("git/"+name+"/"+version+"/BUILD_OK")
            if os.path.isfile("git/"+name+"/"+version+"/NEEDS_BUILD") is False:
                print "updating NEEDS_BUILD for "+name+" "+version
                f = open("git/"+name+"/"+version+"/NEEDS_BUILD","w")
                f.close()
