FROM alpine:3.21 AS builder

ARG QBT_VERSION="5.0.5" \
    BOOST_VERSION_MAJOR="1" \
    BOOST_VERSION_MINOR="86" \
    BOOST_VERSION_PATCH="0" \
    LIBBT_VERSION="RC_1_2" \
    LIBBT_CMAKE_FLAGS=""

LABEL maintainer="emmorts"
LABEL version="5.0.4"
LABEL description="qBittorrent with VPN support"

LABEL org.opencontainers.image.title="qBittorrent VPN"
LABEL org.opencontainers.image.description="A lightweight Docker container running qBittorrent with WireGuard/OpenVPN support"
LABEL org.opencontainers.image.version="5.0.5.0"
LABEL org.opencontainers.image.url="https://github.com/emmorts/docker-qbittorrentvpn"
LABEL org.opencontainers.image.source="https://github.com/emmorts/docker-qbittorrentvpn"
LABEL org.opencontainers.image.licenses="GPL-3.0"
LABEL org.opencontainers.image.created="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
LABEL org.opencontainers.image.authors="tomas@stropus.dev"

LABEL app.qbittorrent.version="5.0.5.0"
LABEL app.libtorrent.version="${LIBBT_VERSION}"
LABEL app.boost.version="${BOOST_VERSION_MAJOR}.${BOOST_VERSION_MINOR}.${BOOST_VERSION_PATCH}"

LABEL build.architecture="$(uname -m)"
LABEL build.date="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

LABEL usage.documentation="https://github.com/emmorts/docker-qbittorrentvpn/blob/master/README.md"
LABEL usage.webui.port="8080"
LABEL usage.bittorrent.port="8999"

# Install build dependencies in a single layer
# Use virtual packages to remove build dependencies later
RUN apk add --no-cache --virtual .build-deps \
        cmake \
        curl \
        g++ \
        git \
        make \
        ninja \
        openssl-dev \
        qt6-qtbase-dev \
        qt6-qttools-dev \
        zlib-dev

# Set compiler and linker options for security and optimization
ENV CFLAGS="-O2 -pipe -fstack-clash-protection -fstack-protector-strong -fno-plt -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS" \
    CXXFLAGS="-O2 -pipe -fstack-clash-protection -fstack-protector-strong -fno-plt -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS" \
    LDFLAGS="-gz -Wl,-O1,--as-needed,--sort-common,-z,now,-z,pack-relative-relocs,-z,relro"

# Build boost, libtorrent and qBittorrent in a single layer to reduce image size
RUN \
    # Download and extract Boost
    curl -L "https://archives.boost.io/release/$BOOST_VERSION_MAJOR.$BOOST_VERSION_MINOR.$BOOST_VERSION_PATCH/source/boost_${BOOST_VERSION_MAJOR}_${BOOST_VERSION_MINOR}_${BOOST_VERSION_PATCH}.tar.gz" | tar xz && \
    mv boost_* boost && \
    # Clone and build libtorrent
    git clone --branch "${LIBBT_VERSION}" --depth 1 --recurse-submodules https://github.com/arvidn/libtorrent.git && \
    cd libtorrent && \
    cmake -B build -G Ninja \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DCMAKE_CXX_STANDARD=20 \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
        -DBOOST_ROOT=/boost \
        -Ddeprecated-functions=OFF \
        ${LIBBT_CMAKE_FLAGS} && \
    cmake --build build -j$(nproc) && \
    cmake --install build && \
    cd .. && \
    # Download and build qBittorrent
    curl -L "https://github.com/qbittorrent/qBittorrent/archive/refs/tags/release-${QBT_VERSION}.tar.gz" | tar xz && \
    cd "qBittorrent-release-${QBT_VERSION}" && \
    cmake -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
        -DBOOST_ROOT=/boost \
        -DGUI=OFF && \
    cmake --build build -j$(nproc) && \
    cmake --install build && \
    # Strip binary to reduce size
    strip /usr/bin/qbittorrent-nox && \
    # Clean up - remove source code and build files
    cd / && \
    rm -rf \
        /boost \
        /libtorrent \
        /qBittorrent-release-* && \
    # Clean up package cache
    apk del .build-deps && \
    rm -rf /var/cache/apk/*

FROM alpine:3.21

# Install runtime dependencies in a single layer
RUN apk add --no-cache \
        bash \
        bc \
        bind-tools \
        dos2unix \
        findutils \
        grep \
        ipcalc \
        iptables \
        libstdc++ \
        moreutils \
        net-tools \
        openresolv \
        openvpn \
        p7zip \
        procps \
        qt6-qtbase \
        qt6-qtbase-sqlite \
        tini \
        tzdata \
        unzip \
        wireguard-tools \
        zip && \
        # Create non-root user and setup WireGuard in the same layer to reduce image size
        adduser -D -H -s /sbin/nologin -u 1000 qbtUser && \
        # Remove check for net.ipv4.conf.all.src_valid_mark=1 in wg-quick,
        # as it can cause issues or is unnecessary within the container's network namespace.
        # The sysctl option is set via docker run/compose instead.
        sed -i /net.ipv4.conf.all.src_valid_mark/d $(which wg-quick) && \
        mkdir -p /tmp && \
        chmod 1777 /tmp && \
        # Remove any package cache that might have been created
        rm -rf /var/cache/apk/*

# Copy qBittorrent binary
COPY --from=builder /usr/bin/qbittorrent-nox /usr/bin/qbittorrent-nox

# Copy configuration scripts
COPY scripts/ /etc/scripts/
COPY openvpn/ /etc/openvpn/
COPY qbittorrent/ /etc/qbittorrent/

# Set execute permissions in a single layer
RUN chmod +x /etc/qbittorrent/*.sh /etc/qbittorrent/*.init /etc/openvpn/*.sh /etc/scripts/*.sh && \
    # Remove any documentation or unnecessary files
    find /etc -name "*.md" -delete && \
    find /etc -name "*.txt" -delete && \
    find /etc -name "README*" -delete

# Create volumes
VOLUME /config /downloads

# Expose ports
EXPOSE 8080 8999 8999/udp

# Use tini as init system and start the main script
ENTRYPOINT ["/sbin/tini", "-g", "--", "/bin/bash", "/etc/scripts/main.sh"]