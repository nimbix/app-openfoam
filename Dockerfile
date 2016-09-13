FROM nimbix/ubuntu-desktop:trusty
MAINTAINER stephen.fox@nimbix.net

RUN apt-get update && apt-get install -y curl software-properties-common
RUN mkdir -p /usr/local/src

RUN add-apt-repository http://dl.openfoam.org/ubuntu
RUN sh -c "wget -O - http://dl.openfoam.org/gpg.key | apt-key add -"

RUN apt-get update && apt-get -y install \
       openfoam4 \
       paraviewopenfoam50

ADD ./scripts /usr/local/scripts

CMD ["/usr/local/scripts/start.sh"]
