FROM garethflowers/svn-server:latest
MAINTAINER carrerfe@gmail.com

ADD setup-my-repos.sh /root/
ADD svnserve.conf /root/
ADD passwd /root/

RUN sh /root/setup-my-repos.sh

EXPOSE 3690

CMD [ "/usr/bin/svnserve", "--daemon", "--foreground", "--root", "/var/opt/svn" ]
