#!/usr/bin/env python

import os
import string
import sys
import tempfile
import  optparse 

usage = "usage: %prog  [-s ] [ -c]  [-t FILE] PACKAGE VERSION\n where \n      -s: use setup packages to define dependency list\n       -c: use current packages to define dependency list\n       -t FILE: temporary file needed for fast dependency collection\n        PACKAGE: eups module needing ordered dependency list\n       VERSION: module version id\nExample: %prog afw 4.7.1.0+1\n         %prog -s afw  4.7.1.0+1\n       %prog afw 86eb12b555d1b8cbfeddb2617c8327111247deed\n"
parser = optparse.OptionParser( usage = usage )
parser.add_option('-s', '--setup', dest='useSetup', help='+setup', action='store_true')
parser.add_option('-c', '--current', dest='useCurrent', help='+current', action='store_true')
parser.add_option('-t', '--temp', dest='filename', help='temporary file needed for fast dependency collection', action="store", type="string")

(options, args) = parser.parse_args()
if len(args) < 2:
    parser.error("provide eups PACKAGE name and relevant version id")

if options.useSetup:
   useSetup = '-s'
else:
   useSetup = ""

if options.useCurrent:
   useCurrent = '-c'
else:
   useCurrent = ""

if options.filename:
   tempName = options.filename 
   useTempFile = True
else:
   useTempFile = False

root_package = args[0]
root_version = args[1]

if useTempFile:
    cmd = "eups list  %s %s --depend --topological %s %s > %s" %( useCurrent, useSetup, root_package, root_version, tempName )
    try:
        os.popen(cmd)
    except:
        print "Failed to execute: %s\n" % (cmd)
        sys.exit(1)

    cmd = "cat %s | sed -e \"s/| //g\" -e \"s/^|*//\"  -e \"s/ \\{1,\\}/ /g\""  %(tempName)
    try:
        f = os.popen(cmd)
    except:
        print "Failed to execute: %s\n" % (cmd)
        sys.exit(1)
else:
    cmd = "eups list  %s %s --depend --topological %s %s | sed -e \"s/| //g\" -e \"s/^|*//\" -e \"s/ \\{1,\\}/ /g\"" % ( useCurrent, useSetup, root_package, root_version )
    try:
        f = os.popen(cmd)
    except:
        print "Failed to execute: %s\n" % (cmd)
        sys.exit(1)

package = []
version = []
try:
    for line in f:
        #print ":%s:" % (line)
        (pkg,vers) = line.split()
        package.append(pkg)
        version.append(vers)
        #print "Forward: %s %s" % (pkg, vers)
finally:
    f.close()

ctr = len(package)
if ctr == 0:
    if useSetup != "":
    	print "Request to use only pre-setup dependencies and found none."
        exit(1)
    else:
        print "No dependencies were found for %s." %(root_package)
        exit(1)


for bkwdIndex in range(ctr-1,-1,-1):
   print "%s %s" % (package[bkwdIndex], version[bkwdIndex])

sys.exit(0)
