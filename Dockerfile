# create an up-to-date base image for everything
FROM alpine:latest AS base

# Update and upgrade the base system
RUN \
    apk --no-cache --update-cache upgrade

# Install runtime dependencies
RUN \
    apk --no-cache add \
        7zip \
        bash \
        curl \
        doas \
        dos2unix \
        ipcalc \
        iptables \
        libcrypto3 \
        libssl3 \
        moreutils \
        net-tools \
        openresolv \
        openvpn \
        procps \
        python3 \
        qt6-qtbase \
        qt6-qtbase-sqlite \
        qt6-qttools \
        tini \
        tzdata \
        unzip \
        wireguard-tools \
        zip \
        zlib

# Image for building
FROM base AS builder

ARG QBT_VERSION="5.0.3" \
    BOOST_VERSION_MAJOR="1" \
    BOOST_VERSION_MINOR="86" \
    BOOST_VERSION_PATCH="0" \
    LIBBT_VERSION="RC_1_2" \
    LIBBT_CMAKE_FLAGS=""

# Alpine Linux build dependencies
RUN \
    apk add \
        cmake \
        git \
        g++ \
        make \
        ninja \
        openssl-dev \
        qt6-qtbase-dev \
        qt6-qttools-dev \
        zlib-dev

# Set compiler and linker options for security and optimization
ENV CFLAGS="-pipe -fstack-clash-protection -fstack-protector-strong -fno-plt -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS" \
    CXXFLAGS="-pipe -fstack-clash-protection -fstack-protector-strong -fno-plt -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS" \
    LDFLAGS="-gz -Wl,-O1,--as-needed,--sort-common,-z,now,-z,pack-relative-relocs,-z,relro"

# Prepare and build boost
RUN \
    wget -O boost.tar.gz "https://archives.boost.io/release/$BOOST_VERSION_MAJOR.$BOOST_VERSION_MINOR.$BOOST_VERSION_PATCH/source/boost_${BOOST_VERSION_MAJOR}_${BOOST_VERSION_MINOR}_${BOOST_VERSION_PATCH}.tar.gz" && \
    tar -xf boost.tar.gz && \
    mv boost_* boost

# Build libtorrent
RUN \
    git clone \
        --branch "${LIBBT_VERSION}" \
        --depth 1 \
        --recurse-submodules \
        https://github.com/arvidn/libtorrent.git && \
    cd libtorrent && \
    cmake \
        -B build \
        -G Ninja \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_CXX_STANDARD=20 \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
        -DBOOST_ROOT=/boost \
        -Ddeprecated-functions=OFF \
        $LIBBT_CMAKE_FLAGS && \
    cmake --build build -j $(nproc) && \
    cmake --install build

# Build qBittorrent
RUN \
    wget "https://github.com/qbittorrent/qBittorrent/archive/refs/tags/release-${QBT_VERSION}.tar.gz" && \
    tar -xf "release-${QBT_VERSION}.tar.gz" && \
    cd "qBittorrent-release-${QBT_VERSION}" && \
    cmake \
        -B build \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
        -DBOOST_ROOT=/boost \
        -DGUI=OFF && \
    cmake --build build -j $(nproc) && \
    cmake --install build

# Generate SBOM
RUN \
    printf "Software Bill of Materials for qbittorrent-nox\n\n" >> /sbom.txt && \
    echo "boost $BOOST_VERSION_MAJOR.$BOOST_VERSION_MINOR.$BOOST_VERSION_PATCH" >> /sbom.txt && \
    cd libtorrent && \
    echo "libtorrent-rasterbar git $(git rev-parse HEAD)" >> /sbom.txt && \
    cd .. && \
    echo "qBittorrent ${QBT_VERSION}" >> /sbom.txt && \
    echo >> /sbom.txt && \
    apk list -I | sort >> /sbom.txt

# Final runtime image
FROM base

# Create non-root user and configure doas
RUN \
    adduser -D -H -s /sbin/nologin -u 1000 qbtUser && \
    echo "permit nopass :root" >> "/etc/doas.d/doas.conf" && \
    # Remove src_valid_mark from wg-quick (required for proper WireGuard operation)
    sed -i /net.ipv4.conf.all.src_valid_mark/d $(which wg-quick)

# Copy qBittorrent binary and SBOM
COPY --from=builder /usr/bin/qbittorrent-nox /usr/bin/qbittorrent-nox
COPY --from=builder /sbom.txt /sbom.txt

# Copy configuration scripts
COPY scripts/ /etc/scripts/
COPY openvpn/ /etc/openvpn/
COPY qbittorrent/ /etc/qbittorrent/

# Set execute permissions
RUN chmod +x /etc/qbittorrent/*.sh /etc/qbittorrent/*.init /etc/openvpn/*.sh /etc/scripts/*.sh

# Create volumes
VOLUME /config /downloads

# Expose ports
EXPOSE 8080 8999 8999/udp

# Use tini as init system and start the main script
ENTRYPOINT ["/sbin/tini", "-g", "--", "/bin/bash", "/etc/scripts/main.sh"]