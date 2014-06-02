#-------------------------------------------------------------------
# This file should be git-archived with buildbot's master.cfg
#-------------------------------------------------------------------

import subprocess 
import shlex

# Need to split tee (piped) command into parts:
command_line='ssh git@git.lsstcorp.org expand "LSST/DMS|LSST/SIM"'
args = shlex.split(command_line)
p1 = subprocess.Popen(args, stdout=subprocess.PIPE)

command_line='sed -e "s/^.*LSST\//LSST\//"  -e "/^hello /d" -e "/ server:/d"'
args = shlex.split(command_line)
p2 = subprocess.Popen(args, stdin=p1.stdout,stdout=subprocess.PIPE)


p1.stdout.close()
output = p2.communicate()[0]
print output


# Now need to exclude certain extraneous directories

