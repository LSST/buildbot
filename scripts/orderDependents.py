#!/usr/bin/env python

import os
import string
import sys
import tempfile
from optparse import OptionParser

usage = "usage: %prog  PACKAGE\n where PACKAGE identifies the root eups module for\n creating an ordered dependency list\nExample: %prog afw"
parser = OptionParser( usage = usage )
(options, args) = parser.parse_args()

if len(args) != 1:
    parser.error("provide a eups PACKAGE name ")
root_package = args[0]

cmd = "eups list -D %s | sed -e \"s/| /||/g\" -e \"s/\\([a-zA-Z]\\)/ \\1/\" -e \"s/^/|/\" -e \"s/\\[.* //\" -e \"s/\\]//\"" % (root_package)

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
