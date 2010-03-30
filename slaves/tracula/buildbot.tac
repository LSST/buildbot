
from twisted.application import service
from buildbot.slave.bot import BuildSlave

basedir = r'/home/buildbot/slave'
buildmaster_host = 'tracula.ncsa.uiuc.edu'
port = 9989
slavename = 'tracula'
passwd = 'accio_build'
keepalive = 600
usepty = 1
umask = None

application = service.Application('buildslave')
s = BuildSlave(buildmaster_host, port, slavename, passwd, basedir,
               keepalive, usepty, umask=umask)
s.setServiceParent(application)

