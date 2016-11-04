FROM debian:jessie

MAINTAINER Viet Pham <viet@webonyx.com>

ENV APP_DEPS \
		gcc \
		libc6-dev \
		libevent-dev \
		ca-certificates \
		make \
		wget \
		perl

RUN apt-get update && apt-get install -y \
		$APP_DEPS \
		supervisor \
		gearman-job-server \
		libevent-2.0-5 \
	--no-install-recommends && rm -r /var/lib/apt/lists/*

# grab gosu for easy step-down from root
ENV GOSU_VERSION 1.7
RUN set -x \
	&& wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
	&& chmod +x /usr/local/bin/gosu \
	&& gosu nobody true

# redis
RUN groupadd -r redis && useradd -r -g redis redis

ENV REDIS_VERSION 3.2.5
ENV REDIS_DOWNLOAD_URL http://download.redis.io/releases/redis-3.2.5.tar.gz
ENV REDIS_DOWNLOAD_SHA1 6f6333db6111badaa74519d743589ac4635eba7a

# for redis-sentinel see: http://redis.io/topics/sentinel
RUN set -ex \
	&& wget -O redis.tar.gz "$REDIS_DOWNLOAD_URL" \
	&& echo "$REDIS_DOWNLOAD_SHA1 *redis.tar.gz" | sha1sum -c - \
	&& mkdir -p /usr/src/redis \
	&& tar -xzf redis.tar.gz -C /usr/src/redis --strip-components=1 \
	&& rm redis.tar.gz \
	\
# Disable Redis protected mode [1] as it is unnecessary in context
# of Docker. Ports are not automatically exposed when running inside
# Docker, but rather explicitely by specifying -p / -P.
# [1] https://github.com/antirez/redis/commit/edd4d555df57dc84265fdfb4ef59a4678832f6da
	&& grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 1$' /usr/src/redis/src/server.h \
	&& sed -ri 's!^(#define CONFIG_DEFAULT_PROTECTED_MODE) 1$!\1 0!' /usr/src/redis/src/server.h \
	&& grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 0$' /usr/src/redis/src/server.h \
# for future reference, we modify this directly in the source instead of just supplying a default configuration flag because apparently "if you specify any argument to redis-server, [it assumes] you are going to specify everything"
# see also https://github.com/docker-library/redis/issues/4#issuecomment-50780840
# (more exactly, this makes sure the default behavior of "save on SIGTERM" stays functional by default)
	\
	&& make -C /usr/src/redis \
	&& make -C /usr/src/redis install \
	&& rm -r /usr/src/redis

RUN mkdir /redis-data && chown redis:redis /redis-data
VOLUME /redis-data

# memcached
RUN groupadd -r memcache && useradd -r -g memcache memcache

ENV MEMCACHED_VERSION 1.4.33
ENV MEMCACHED_SHA1 e343530c55946ccbdd78c488355b02eaf90b3b46

RUN wget -O memcached.tar.gz "http://memcached.org/files/memcached-$MEMCACHED_VERSION.tar.gz" \
	&& echo "$MEMCACHED_SHA1  memcached.tar.gz" | sha1sum -c - \
	&& mkdir -p /usr/src/memcached \
	&& tar -xzf memcached.tar.gz -C /usr/src/memcached --strip-components=1 \
	&& rm memcached.tar.gz \
	&& cd /usr/src/memcached \
	&& ./configure \
	&& make -j$(nproc) \
	&& make install \
	&& cd / && rm -rf /usr/src/memcached


RUN apt-get purge -y --auto-remove $APP_DEPS

# forward gearman log to docker log collector
RUN ln -sf /dev/stdout /var/log/gearmand.log

COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY apps.conf /etc/supervisor/conf.d

EXPOSE 7001 6379 11211 4730


CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]