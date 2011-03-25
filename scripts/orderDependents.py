#!/usr/bin/env python

import os
import string
import sys
import tempfile
import  optparse 

usage = "usage: %prog  [-s]  [-t FILE] PACKAGE\n where \n      -s: use setup packages to define dependency list\n       -t FILE: temporary file needed for fast dependency collection\n        PACKAGE: eups module needing ordered dependency list\nExample: %prog afw\n         %prog -s datarel"
parser = optparse.OptionParser( usage = usage )
parser.add_option('-s', '--setup', dest='useSetup', help='+setup', action='store_true')
parser.add_option('-t', '--temp', dest='filename', help='temporary file needed for fast dependency collection', action="store", type="string")

(options, args) = parser.parse_args()
if len(args) < 1:
    parser.error("provide an eups PACKAGE name ")

if options.useSetup:
   useSetup = '-s'
else:
   useSetup = ""
root_package = args[0]

if options.filename:
   tempName = options.filename 
   useFastMethod = True
else:
   useFastMethod = False

root_package = args[0]

if useFastMethod:
    # Alternate and faster method than 'eups list -D' to build dependency order.
    # Need stderr from setup command; toss stdout
    cmd = "setup -N -v %s  2> %s" %(root_package, tempName)
    try:
        os.popen(cmd)
    except:
        print "Failed to execute: %s\n" % (cmd)
        sys.exit(1)

    cmd = "cat %s | grep -v Unable | grep -v Product | sed -e \"s/Setting up: //\" -e \"s/ Flavor:.*Version://\" -e \"s/| /||/g\"  -e \"s/^/|/\" -e \"s/|\\([a-zA-Z]\\)/| \\1/\" " %(tempName)
    try:
        f = os.popen(cmd)
    except:
        print "Failed to execute: %s\n" % (cmd)
        sys.exit(1)
else:
    cmd = "eups list %s -D %s | sed -e \"s/| /||/g\" -e \"s/\\([a-zA-Z]\\)/ \\1/\" -e \"s/^/|/\" -e \"s/\\[.* //\" -e \"s/\\]//\"" % (useSetup, root_package)
    try:
        f = os.popen(cmd)
    except:
        print "Failed to execute: %s\n" % (cmd)
        sys.exit(1)

levels= []
packages = []
versions = []
fromIndex = []
try:
    ctr = 0
    for line in f:
        try:
            (bars,package,version) = line.split()
        except:
            continue
        levelCount = bars.count("|")
        #print "%i:%s:%s:%s" % (levelCount,bars,package,version)
        levels.append(levelCount)
        packages.append(package)
        versions.append(version)
finally:
    f.close()

levelsSize = len(levels)
if levelsSize == 0:
    if useSetup != "":
    	print "Request to use only pre-setup dependencies and found none."
        exit(1)
    else:
        print "No dependencies were found for %s." %(root_package)
        exit(1)

lastLevel = 1
curIndex = 1
curLevel = levels[curIndex]
ForwardProcessing = True
while ForwardProcessing :
    #print "lastLevel: %i curLevel: %i  curIndex: %i curPkg: %s" % (lastLevel, curLevel, curIndex, packages[curIndex])
    if lastLevel >= curLevel :
        # Moving backwards, find previous entry <= curLevel
        for bkwdIndex in range(curIndex - 1, 0, -1):
            #print "bkwdIndex: %i" % (bkwdIndex)
            if levels[bkwdIndex] >= curLevel:
                # setup packages[bkwdIndex] versions[bkwdIndex]
                print "%s %s" % (packages[bkwdIndex], versions[bkwdIndex])
                fromIndex.append(bkwdIndex) 
                levels[bkwdIndex] = 0
            elif levels[bkwdIndex] == 0:
                # Previously processed
                #print "previously processed index: %i  %s" % (bkwdIndex, packages[bkwdIndex])
                continue
            else: 
                # found previous entry > curLevel; done w/ loop
                break
    # Setup to progress forward
    if (curIndex + 1) < levelsSize:
        lastLevel = curLevel
        curIndex = curIndex + 1
        curLevel = levels[curIndex]
    else: # finished searching for dependency nests, process remaining
        ForwardProcessing = False


# Process last nest
for bkwdIndex in range(levelsSize-1,-1,-1):
    if levels[bkwdIndex] == 0:
        continue
    else: 
        # setup packages[fwdIndex] versions[fwdIndex]
        print "%s %s" % (packages[bkwdIndex], versions[bkwdIndex])
        fromIndex.append(bkwdIndex)
        levels[bkwdIndex] = 0

#print "Final dependency levels"
#for i in range(levelsSize):
#    orgPos = fromIndex[i]
#    print "Index: %i  Level: %i Package: %s" % (i, levels[orgPos], packages[orgPos])

sys.exit(0)
