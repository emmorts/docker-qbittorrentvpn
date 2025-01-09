# Builder stage for boost, libtorrent and qBittorrent
FROM debian:bullseye-slim AS builder

# Install build dependencies in a single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    g++ \
    git \
    jq \
    libssl-dev \
    libxml2-utils \
    ninja-build \
    pkg-config \
    qtbase5-dev \
    qttools5-dev \
    unzip \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Build boost
RUN BOOST_VERSION_DOT=$(curl -sX GET "https://www.boost.org/feed/news.rss" | xmllint --xpath '//rss/channel/item/title/text()' - | awk -F 'Version' '{print $2 FS}' - | sed -e 's/Version//g;s/\ //g' | xargs | awk 'NR==1{print $1}' -) \
    && BOOST_VERSION=$(echo ${BOOST_VERSION_DOT} | head -n 1 | sed -e 's/\./_/g') \
    && curl -L https://boostorg.jfrog.io/artifactory/main/release/${BOOST_VERSION_DOT}/source/boost_${BOOST_VERSION}.tar.gz | tar xz \
    && cd boost_${BOOST_VERSION} \
    && ./bootstrap.sh --prefix=/usr \
    && ./b2 --prefix=/usr install

# Build libtorrent-rasterbar
RUN LIBTORRENT_ASSETS=$(curl -sX GET "https://api.github.com/repos/arvidn/libtorrent/releases" | jq '.[] | select(.prerelease==false) | select(.target_commitish=="RC_1_2") | .assets_url' | head -n 1 | tr -d '"') \
    && LIBTORRENT_DOWNLOAD_URL=$(curl -sX GET ${LIBTORRENT_ASSETS} | jq '.[0] .browser_download_url' | tr -d '"') \
    && curl -L ${LIBTORRENT_DOWNLOAD_URL} | tar xz \
    && cd libtorrent-rasterbar* \
    && cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=/usr -DCMAKE_CXX_STANDARD=17 \
    && cmake --build build --parallel $(nproc) \
    && cmake --install build

# Build qBittorrent
RUN QBITTORRENT_RELEASE=$(curl -sX GET "https://api.github.com/repos/qBittorrent/qBittorrent/tags" | jq '.[] | select(.name | index ("alpha") | not) | select(.name | index ("beta") | not) | select(.name | index ("rc") | not) | .name' | head -n 1 | tr -d '"') \
    && curl -L "https://github.com/qbittorrent/qBittorrent/archive/${QBITTORRENT_RELEASE}.tar.gz" | tar xz \
    && cd qBittorrent-${QBITTORRENT_RELEASE} \
    && cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local -DGUI=OFF -DCMAKE_CXX_STANDARD=17 \
    && cmake --build build --parallel $(nproc) \
    && cmake --install build

# Final stage
FROM debian:bullseye-slim

# Create necessary directories and modify user in a single layer
RUN usermod -u 99 nobody \
    && mkdir -p /downloads /config/qBittorrent /etc/openvpn /etc/qbittorrent /etc/scripts

# Install runtime dependencies in a single layer
RUN echo "deb http://deb.debian.org/debian/ unstable main" > /etc/apt/sources.list.d/unstable-wireguard.list \
    && echo "deb http://deb.debian.org/debian/ bullseye non-free" > /etc/apt/sources.list.d/non-free-unrar.list \
    && printf 'Package: *\nPin: release a=unstable\nPin-Priority: 150\n' > /etc/apt/preferences.d/limit-unstable \
    && printf 'Package: *\nPin: release a=non-free\nPin-Priority: 150\n' > /etc/apt/preferences.d/limit-non-free \
    && apt-get update && apt-get install -y --no-install-recommends \
    dos2unix \
    inetutils-ping \
    ipcalc \
    iptables \
    kmod \
    libqt5network5 \
    libqt5xml5 \
    libqt5sql5 \
    libssl1.1 \
    moreutils \
    net-tools \
    openresolv \
    openvpn \
    p7zip-full \
    procps \
    unrar \
    unzip \
    wireguard-tools \
    zip \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i /net\.ipv4\.conf\.all\.src_valid_mark/d `which wg-quick`

# Copy built artifacts from builder stage
COPY --from=builder /usr/local/bin/qbittorrent-nox /usr/local/bin/
COPY --from=builder /usr/lib/libboost_* /usr/lib/
COPY --from=builder /usr/lib/libtorrent-rasterbar.so* /usr/lib/

# Copy configuration files
COPY scripts/ /etc/scripts/
COPY openvpn/ /etc/openvpn/
COPY qbittorrent/ /etc/qbittorrent/

# Set execute permissions
RUN chmod +x /etc/qbittorrent/*.sh /etc/qbittorrent/*.init /etc/openvpn/*.sh /etc/scripts/*.sh

# Define volumes and ports
VOLUME /config /downloads
EXPOSE 8080 8999 8999/udp

CMD ["/bin/bash", "/etc/scripts/main.sh"]