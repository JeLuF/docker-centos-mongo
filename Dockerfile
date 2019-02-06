FROM centos:7

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -r mongodb && useradd -r -g mongodb mongodb

RUN set -eux; \
	yum update -y; \
        yum install -y epel-release; \
	yum install -y \
		jq \
		numactl \
                wget gnupg2\
	; \
	if ! command -v ps > /dev/null; then \
		yum install -y procps; \
	fi;

# grab gosu for easy step-down from root (https://github.com/tianon/gosu/releases)
ENV GOSU_VERSION 1.10
# grab "js-yaml" for parsing mongod's YAML config files (https://github.com/nodeca/js-yaml/releases)
ENV JSYAML_VERSION 3.10.0

RUN set -ex; \
	\
	Arch="amd64"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$Arch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$Arch.asc"; \
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	command -v gpgconf && gpgconf --kill all || :; \
	rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	chmod +x /usr/local/bin/gosu; \
	gosu nobody true; \
	\
	wget -O /js-yaml.js "https://github.com/nodeca/js-yaml/raw/${JSYAML_VERSION}/dist/js-yaml.js";

RUN mkdir /docker-entrypoint-initdb.d

ENV GPG_KEYS 68818c72e52529d4
RUN set -ex; \
	for key in $GPG_KEYS; do \
		gpg --batch --keyserver keys.gnupg.net --recv-keys "$key"; \
	done; \
	gpg --batch --export --armor $GPG_KEYS > /tmp/mongodb.asc; \
        rpmkeys --import /tmp/mongodb.asc; \
	command -v gpgconf && gpgconf --kill all || :;

# Allow build-time overrides (eg. to build image with MongoDB Enterprise version)
# Options for MONGO_PACKAGE: mongodb-org OR mongodb-enterprise
# Options for MONGO_REPO: repo.mongodb.org OR repo.mongodb.com
# Example: docker build --build-arg MONGO_PACKAGE=mongodb-enterprise --build-arg MONGO_REPO=repo.mongodb.com .
ARG MONGO_PACKAGE=mongodb-org
ARG MONGO_REPO=repo.mongodb.org
ENV MONGO_PACKAGE=${MONGO_PACKAGE} MONGO_REPO=${MONGO_REPO}

ENV MONGO_MAJOR 4.0
ENV MONGO_VERSION 4.0.6

RUN echo -e "[mongodb-org]\n\
name=MongoDB Repository\n\
baseurl=https://${MONGO_REPO}/yum/redhat/\$releasever/${MONGO_PACKAGE}/${MONGO_MAJOR}/x86_64/\n\
gpgcheck=1\n\
enabled=1" | tee /etc/yum.repos.d/mongodb.repo

RUN cat /etc/yum.repos.d/mongodb.repo
RUN set -x \
	&& yum install -y \
		${MONGO_PACKAGE}-$MONGO_VERSION \
		${MONGO_PACKAGE}-server-$MONGO_VERSION \
		${MONGO_PACKAGE}-shell-$MONGO_VERSION \
		${MONGO_PACKAGE}-mongos-$MONGO_VERSION \
		${MONGO_PACKAGE}-tools-$MONGO_VERSION \
	&& rm -rf /var/lib/mongodb \
	&& mv /etc/mongod.conf /etc/mongod.conf.orig

RUN mkdir -p /data/db /data/configdb \
	&& chown -R mongodb:mongodb /data/db /data/configdb
VOLUME /data/db /data/configdb

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

EXPOSE 27017
CMD ["mongod"]
