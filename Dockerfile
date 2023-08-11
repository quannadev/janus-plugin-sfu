FROM debian:buster as JanusGateway

## -----------------------------------------------------------------------------
## Install dependencies
## -----------------------------------------------------------------------------
RUN set -xe \
    && apt-get update \
    && apt-get -y --no-install-recommends install \
    autoconf \
    automake \
    awscli \
    ca-certificates \
    curl \
    ffmpeg \
    gengetopt \
    git \
    libavformat-dev \
    libavcodec-dev \
    libconfig-dev \
    libcurl4-openssl-dev \
    libglib2.0-dev \
    libjansson-dev \
    libmicrohttpd-dev \
    libogg-dev \
    libopus-dev \
    libsofia-sip-ua-dev \
    libssl-dev \
    libtool \
    m4 \
    make \
    pkg-config \
    wget

RUN apt-get -y --no-install-recommends install \
    ninja-build \
    python3 \
    python3-pip \
    python3-setuptools \
    python3-wheel

## -----------------------------------------------------------------------------
## Install latest libnice (recommended by Janus devs)
## -----------------------------------------------------------------------------
RUN pip3 install meson \
    && git clone https://gitlab.freedesktop.org/libnice/libnice \
    && cd libnice \
    && meson --prefix=/usr build \
    && ninja -C build \
    && ninja -C build install

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

## -----------------------------------------------------------------------------
## Build Janus Gateway
## -----------------------------------------------------------------------------
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

## -----------------------------------------------------------------------------
## Build Janus Audio plugins
## -----------------------------------------------------------------------------
FROM --platform=linux/x86_64 rust:1.70-buster as JanusGatewayPlugins

RUN set -xe \
    && apt-get update \
    && apt-get -y --no-install-recommends install libjansson-dev

WORKDIR /build

COPY Cargo.* ./
RUN mkdir ./src && touch src/lib.rs
RUN cargo build --release
COPY src ./src
RUN cargo build --release

## -----------------------------------------------------------------------------
## Build Janus Gateway Runtime
## -----------------------------------------------------------------------------

FROM debian:buster as JanusRuntime
ARG PLUGIN=libjanus_plugin_sfu.so
WORKDIR /opt/janus
COPY --from=JanusGateway /opt/janus /opt/janus
COPY --from=JanusGatewayPlugins /build/target/release/${PLUGIN} /opt/janus/lib/janus/plugins/${PLUGIN}

EXPOSE 8088 8188 8089 8189 7088 7188 7089 7189