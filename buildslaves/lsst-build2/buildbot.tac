
import os

from twisted.application import service
from buildslave.bot import BuildSlave

basedir = r'/lsst/home/buildbot/RHEL6/buildslaves/lsst-build2'
rotateLength = 10000000
maxRotatedFiles = 5

# if this is a relocatable tac file, get the directory containing the TAC
if basedir == '.':
    import os.path
    basedir = os.path.abspath(os.path.dirname(__file__))

# note: this line is matched against to check that this is a buildslave
# directory; do not edit it.
application = service.Application('buildslave')

try:
  from twisted.python.logfile import LogFile
  from twisted.python.log import ILogObserver, FileLogObserver
  logfile = LogFile.fromFullPath(os.path.join(basedir, "twistd.log"), rotateLength=rotateLength,
                                 maxRotatedFiles=maxRotatedFiles)
  application.setComponent(ILogObserver, FileLogObserver(logfile).emit)
except ImportError:
  # probably not yet twisted 8.2.0 and beyond, can't set log yet
  pass

buildmaster_host = 'lsst-build.ncsa.illinois.edu'
port = 9989
slavename = 'lsst-build2.ncsa.illinois.edu'
passwd = 'CHANGE_TO_THE_PRODUCTION_PASS'
keepalive = 600
usepty = 0
umask = 002
maxdelay = 300

s = BuildSlave(buildmaster_host, port, slavename, passwd, basedir,
               keepalive, usepty, umask=umask, maxdelay=maxdelay)
s.setServiceParent(application)

