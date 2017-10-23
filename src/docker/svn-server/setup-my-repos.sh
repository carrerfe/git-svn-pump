#!/bin/sh

cd /var/opt/svn
svnadmin create testrepo
cp /root/passwd testrepo/conf/
cp /root/svnserve.conf testrepo/conf/
