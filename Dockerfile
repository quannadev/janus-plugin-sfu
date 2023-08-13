## -----------------------------------------------------------------------------
## Build Janus Audio plugins
## -----------------------------------------------------------------------------
FROM --platform=linux/x86_64 rust:1.63-slim-bullseye as JanusGateway

RUN set -xe \
    && apt-get update \
    && apt-get -y --no-install-recommends install \
    libjansson-dev \
    build-essential \
    git \
    gtk-doc-tools \
    libavutil-dev \
    libavformat-dev \
    libavcodec-dev \
    libmicrohttpd-dev \
    libjansson-dev \
    libssl-dev \
    libsofia-sip-ua-dev \
    libglib2.0-dev \
    libopus-dev \
    libogg-dev \
    libcurl4-openssl-dev \
    liblua5.3-dev \
    libconfig-dev \
    libusrsctp-dev \
    libwebsockets-dev \
    libnanomsg-dev \
    librabbitmq-dev \
    pkg-config \
    gengetopt

## -----------------------------------------------------------------------------
## Install latest libnice (recommended by Janus devs)
## -----------------------------------------------------------------------------
RUN cd /tmp && \
	git clone https://gitlab.freedesktop.org/libnice/libnice && \
	cd libnice && \
	git checkout 0.1.17 && \
	./autogen.sh && \
	./configure --prefix=/usr && \
	make && \
	make install


## -----------------------------------------------------------------------------
## Install libsrtp (with --enable-openssl option)
## -----------------------------------------------------------------------------
ARG LIBSRTP_VERSION=2.3.0

RUN wget https://github.com/cisco/libsrtp/archive/v${LIBSRTP_VERSION}.tar.gz \
    && tar xfv v${LIBSRTP_VERSION}.tar.gz \
    && cd libsrtp-${LIBSRTP_VERSION} \
    && ./configure --prefix=/usr --enable-openssl \
    && make shared_library \
    && make install

WORKDIR /build

COPY Cargo.* ./
RUN mkdir ./src && touch src/lib.rs
RUN cargo build --release
COPY src ./src
RUN cargo build --release

WORKDIR /janus

ARG JANUS_GATEWAY_COMMIT='v0.14.0'

RUN set -xe \
    && JANUS_GATEWAY_BUILD_DIR=$(mktemp -d) \
    && cd "${JANUS_GATEWAY_BUILD_DIR}" \
    && git clone 'https://github.com/meetecho/janus-gateway' . \
    && git checkout "${JANUS_GATEWAY_COMMIT}" \
    && ./autogen.sh \
    && ./configure --prefix=/opt/janus --enable-post-processing  \
    && make -j $(nproc) \
    && make install \
    && make configs \
    && rm -rf "${JANUS_GATEWAY_BUILD_DIR}"

ARG PLUGIN=libjanus_plugin_sfu.so
RUN cp /build/target/release/${PLUGIN} /opt/janus/lib/janus/plugins/${PLUGIN}

RUN set -xe \
    && apt-get remove -y \
    autoconf \
    automake \
    git \
    libtool \
    m4 \
    make \
    ninja-build \
    wget

WORKDIR /opt/janus

EXPOSE 8088 8188 8089 8189 7088 7188 7089 7189

#CMD ["/opt/janus/bin/janus", "-F", "/opt/janus/etc/janus"]