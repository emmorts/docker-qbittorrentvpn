# qBittorrent with VPN

A lightweight Docker container running latest [qBittorrent](https://github.com/qbittorrent/qBittorrent) with WireGuard/OpenVPN support and built-in killswitch.

## Features

- Ultra-lightweight Alpine Linux base (41.3 MB total image size, more than 4x smaller than [DyonR/docker-qbittorrentvpn](https://github.com/DyonR/docker-qbittorrentvpn))
- Latest qBittorrent v5.0.4 with libtorrent, compiled from source
- WireGuard and OpenVPN support with automatic killswitch
- Enhanced error handling and reliability
- Configurable UID/GID for seamless file permissions
- Unraid-compatible

## Quick Start

```bash
docker run -d \
    --name=qbittorrent \
    -v /your/config/:/config \
    -v /your/downloads/:/downloads \
    -e "VPN_ENABLED=yes" \
    -e "VPN_TYPE=wireguard" \
    -e "LAN_NETWORK=192.168.0.0/24" \
    -p 8080:8080 \
    -p 8999:8999 \
    -p 8999:8999/udp \
    --cap-add NET_ADMIN \
    --sysctl "net.ipv4.conf.all.src_valid_mark=1" \
    --restart unless-stopped \
    ghcr.io/emmorts/docker-qbittorrentvpn:latest
```

After starting, access the WebUI at `https://your-ip:8080` with:
- Username: `admin`
- Password: `adminadmin`

## Configuration

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `VPN_ENABLED` | Enable VPN functionality | `yes` |
| `VPN_TYPE` | Choose VPN protocol | `wireguard` or `openvpn` |
| `LAN_NETWORK` | Your local network CIDR | `192.168.0.0/24` |

### Optional Environment Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `NAME_SERVERS` | DNS servers | `1.1.1.1,1.0.0.1` | `8.8.8.8,8.8.4.4` |
| `PUID` | User ID for files | `99` | `1000` |
| `PGID` | Group ID for files | `100` | `1000` |
| `ENABLE_SSL` | Enable HTTPS for WebUI | `yes` | `no` |
| `LEGACY_IPTABLES` | Use legacy iptables | - | `yes` |
| `INSTALL_PYTHON3` | Install Python 3 | `no` | `yes` |

For a complete list of environment variables, see the [Environment Variables wiki page](https://github.com/emmorts/docker-qbittorrentvpn/wiki/Environment-Variables).

### Volumes

| Volume | Purpose | Required |
|--------|----------|----------|
| `/config` | Configuration files | Yes |
| `/downloads` | Download location | Yes |

### Ports

| Port | Protocol | Purpose |
|------|----------|----------|
| `8080` | TCP | WebUI |
| `8999` | TCP/UDP | BitTorrent |

## VPN Configuration

### WireGuard Setup

1. Place your `wg0.conf` in `/config/wireguard/`
2. Ensure `VPN_TYPE=wireguard`
3. Start the container

For IPv6 support:
- Add IPv6 range to `LAN_NETWORK`
- Add `--sysctl net.ipv6.conf.all.disable_ipv6=0` to docker run

### OpenVPN Setup

1. Place your OpenVPN configuration file (`.ovpn` or `.conf`) in `/config/openvpn/`
2. Set `VPN_TYPE=openvpn`
3. If your configuration references external files:
   - Certificate files (`.crt`) can be placed in the same directory
   - If your config references `update-resolv-conf`, you can provide a custom script in the same directory
4. If using credentials:
   ```conf
   # /config/openvpn/credentials.conf
   username
   password
   ```
   Add to your OpenVPN config:
   ```
   auth-user-pass credentials.conf
   ```

The container will automatically detect and properly handle all referenced files as long as they are placed in the `/config/openvpn/` directory.

## Docker Compose

```yaml
version: '3'
services:
  qbittorrent:
    container_name: qbittorrent
    image: ghcr.io/emmorts/docker-qbittorrentvpn:latest
    environment:
      - VPN_ENABLED=yes
      - VPN_TYPE=wireguard
      - LAN_NETWORK=192.168.0.0/24
    volumes:
      - ./config:/config
      - ./downloads:/downloads
    ports:
      - 8080:8080
      - 8999:8999
      - 8999:8999/udp
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    restart: unless-stopped
```

## Support

For issues and feature requests, please [open an issue](https://github.com/emmorts/docker-qbittorrentvpn/issues) on GitHub.

## Credits

This project is a fork of [DyonR/docker-qbittorrentvpn](https://github.com/DyonR/docker-qbittorrentvpn) with significant improvements in size optimization, reliability, and error handling.