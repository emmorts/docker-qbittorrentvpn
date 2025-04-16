#!/bin/bash

if [[ -f "/etc/scripts/constants.sh" ]]; then
    source "/etc/scripts/constants.sh"
else
    echo "[ERROR] Critical dependency /etc/scripts/constants.sh not found. Exiting." >&2
    exit 1
fi

readonly QBIT_WEBUI_PORT=8080
readonly QBIT_TORRENT_TCP_PORT=8999
readonly QBIT_TORRENT_UDP_PORT=8999

log_info "Waiting for VPN tunnel interface (${VPN_DEVICE_TYPE}) to appear..."
max_wait_seconds=60
count=0
tunnel_detected=false
while [[ ${count} -lt ${max_wait_seconds} ]]; do
    if ip link show "${VPN_DEVICE_TYPE}" &>/dev/null; then
        log_info "VPN tunnel interface ${VPN_DEVICE_TYPE} detected."
        tunnel_detected=true
        break
    fi
    sleep 1
    count=$((count + 1))
done

if [[ "${tunnel_detected}" != "true" ]]; then
    log_error_and_exit "VPN tunnel interface ${VPN_DEVICE_TYPE} not found after ${max_wait_seconds} seconds. Aborting firewall setup."
fi

log_info "Detecting local network configuration..."

docker_interface=$(ip -4 route show default | awk '{print $5}' | head -n1)
if [[ -z "${docker_interface}" ]]; then
    log_warning "Failed to detect default network interface via default route. Trying fallback detection..."
    # fallback: Find first non-loopback, non-vpn interface link
    if [[ -z "${VPN_DEVICE_TYPE}" ]]; then
        log_warning "VPN_DEVICE_TYPE not set during interface detection fallback, results may be inaccurate."
        docker_interface=$(ip -o link show | grep -v -E '\s(lo):' | head -n1 | awk -F': ' '{print $2}')
    else
        docker_interface=$(ip -o link show | grep -v -E '\s(lo|${VPN_DEVICE_TYPE}):' | head -n1 | awk -F': ' '{print $2}')
    fi
    docker_interface=${docker_interface%@*}
fi

validate_value "Local network interface" "${docker_interface}" "Cannot determine interface for local routing/firewall rules."
log_info "Detected local network interface: ${docker_interface}"

docker_ip_cidr=$(ip -4 -o addr show dev "${docker_interface}" | awk '{print $4; exit}') # get first IPv4 CIDR found
validate_value "Local IP/CIDR" "${docker_ip_cidr}" "Failed to get IP address for ${docker_interface}."
docker_ip=$(echo "${docker_ip_cidr}" | cut -d/ -f1)
log_info "Detected local IP/CIDR: ${docker_ip_cidr}"

log_debug "Docker IP defined as ${docker_ip}"

log_info "Setting up routes for LAN_NETWORK..."
DEFAULT_GATEWAY=$(ip -4 route list 0/0 | cut -d ' ' -f 3)
validate_value "Default Gateway" "${DEFAULT_GATEWAY}" "Cannot determine default gateway for LAN routing."

if [[ -z "${LAN_NETWORK}" ]]; then
    log_warning "LAN_NETWORK environment variable is not set. WebUI/Additional Ports might not be accessible from your local network."
    lan_network_list=()
else
    IFS=',' read -ra lan_network_list <<< "${LAN_NETWORK}"
    log_info "Processing LAN networks: ${LAN_NETWORK}"
fi

for lan_network_item in "${lan_network_list[@]}"; do
	lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

    if [[ -z "${lan_network_item}" ]]; then
        log_warning "Skipping empty item in LAN_NETWORK list."
        continue
    fi

	log_info "Adding route for ${lan_network_item} via ${DEFAULT_GATEWAY} dev ${docker_interface}"
	ip route add "${lan_network_item}" via "${DEFAULT_GATEWAY}" dev "${docker_interface}" || \
        log_warning "Failed to add route for ${lan_network_item}. Network may be unreachable."
done

log_info "Current IP routes:"
log_info "--------------------"
ip route || log_warning "Failed to display IP routes."
log_info "--------------------"

log_info "Configuring iptables rules..."

log_info "Flushing existing rules..."
iptables -F
iptables -X
ip6tables -F 2>/dev/null || true
ip6tables -X 2>/dev/null || true

log_info "Setting default DROP policies..."
iptables -P INPUT DROP
iptables -P FORWARD DROP # forwarding should not be needed
iptables -P OUTPUT DROP

ip6tables -P INPUT DROP 1>&- 2>&- || true
ip6tables -P FORWARD DROP 1>&- 2>&- || true
ip6tables -P OUTPUT DROP 1>&- 2>&- || true

log_info "Allowing loopback and established/related connections..."
# IPv4
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
# IPv6 (best effort, ignore errors if IPv6 is disabled)
ip6tables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
ip6tables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true
ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
ip6tables -A OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

log_info "Allowing VPN tunnel traffic..."
validate_value "VPN Device Type" "${VPN_DEVICE_TYPE}"
validate_value "VPN Protocol" "${VPN_PROTOCOL}"
validate_value "VPN Port" "${VPN_PORT}"

# allow all traffic over the VPN tunnel interface
iptables -A INPUT -i "${VPN_DEVICE_TYPE}" -j ACCEPT
iptables -A OUTPUT -o "${VPN_DEVICE_TYPE}" -j ACCEPT
# allow the VPN connection itself to establish over the docker interface
log_info "Allowing VPN connection establishment (${VPN_PROTOCOL} port ${VPN_PORT})..."
if [[ "${VPN_PROTOCOL}" == "udp" ]]; then
    iptables -A OUTPUT -o "${docker_interface}" -p udp --dport "${VPN_PORT}" -j ACCEPT
else
    iptables -A OUTPUT -o "${docker_interface}" -p tcp --dport "${VPN_PORT}" -j ACCEPT
fi

log_info "Allowing local docker network communication (${docker_ip_cidr})..."
# allow traffic within the container's own Docker network
iptables -A INPUT -i "${docker_interface}" -s "${docker_ip_cidr}" -d "${docker_ip_cidr}" -j ACCEPT
iptables -A OUTPUT -o "${docker_interface}" -s "${docker_ip_cidr}" -d "${docker_ip_cidr}" -j ACCEPT

# allow imcoming Connections (LAN/VPN -> Container)
log_info "Allowing incoming connections to application ports..."
# WebUI Port (from anywhere allowed by routing, typically LAN)
iptables -A INPUT -i "${docker_interface}" -p tcp --dport "${QBIT_WEBUI_PORT}" -j ACCEPT

# torrent Ports (primarily needed if VPN provider forwards the port)
iptables -A INPUT -i "${docker_interface}" -p tcp --dport "${QBIT_TORRENT_TCP_PORT}" -j ACCEPT
iptables -A INPUT -i "${docker_interface}" -p udp --dport "${QBIT_TORRENT_UDP_PORT}" -j ACCEPT

# additional ports (incoming)
if [[ -n "${ADDITIONAL_PORTS}" ]]; then
	IFS=',' read -ra additional_port_list <<< "${ADDITIONAL_PORTS}"
	log_info "Allowing additional incoming ports: ${ADDITIONAL_PORTS}"
	for additional_port_item in "${additional_port_list[@]}"; do
		additional_port_item=$(echo "${additional_port_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
        if [[ -z "${additional_port_item}" || ! "${additional_port_item}" =~ ^[0-9]+$ ]]; then
             log_warning "Skipping invalid additional port: ${additional_port_item}"
            continue
        fi
		log_info "Allowing incoming TCP/UDP for port ${additional_port_item} on ${docker_interface}"
		iptables -A INPUT -i "${docker_interface}" -p tcp --dport "${additional_port_item}" -j ACCEPT
		iptables -A INPUT -i "${docker_interface}" -p udp --dport "${additional_port_item}" -j ACCEPT
	done
fi

# allow outgoing connections (container -> LAN) ONLY for specified ports/networks
if [[ ${#lan_network_list[@]} -gt 0 ]]; then
    log_info "Allowing outgoing connections to LAN for specific services..."
    for lan_network_item in "${lan_network_list[@]}"; do
        lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
        if [[ -z "${lan_network_item}" ]]; then continue; fi

        log_info "Allowing outgoing to ${lan_network_item} for WebUI (${QBIT_WEBUI_PORT})"
        iptables -A OUTPUT -o "${docker_interface}" -d "${lan_network_item}" -p tcp --dport "${QBIT_WEBUI_PORT}" -j ACCEPT

        # additional ports (outgoing to LAN)
        if [[ -n "${ADDITIONAL_PORTS}" ]]; then
            # reuse list from above - assumes it was populated if ADDITIONAL_PORTS is set
            for additional_port_item in "${additional_port_list[@]}"; do
                 additional_port_item=$(echo "${additional_port_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
                 if [[ -z "${additional_port_item}" || ! "${additional_port_item}" =~ ^[0-9]+$ ]]; then continue; fi
                 log_info "Allowing outgoing TCP/UDP to ${lan_network_item} for port ${additional_port_item}"
                 iptables -A OUTPUT -o "${docker_interface}" -d "${lan_network_item}" -p tcp --dport "${additional_port_item}" -j ACCEPT
                 iptables -A OUTPUT -o "${docker_interface}" -d "${lan_network_item}" -p udp --dport "${additional_port_item}" -j ACCEPT
            done
        fi
    done
else
    log_info "No LAN networks defined, skipping LAN-specific outgoing rules."
fi


# --- ICMP ---
log_info "Allowing necessary ICMP types..."
# allow outgoing pings (needed for health checks, etc.)
iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT
# allow incoming ping replies
# allow incoming Time Exceeded, Destination Unreachable
iptables -A INPUT -p icmp --icmp-type time-exceeded -j ACCEPT
iptables -A INPUT -p icmp --icmp-type destination-unreachable -j ACCEPT


log_info "iptables configuration complete."
log_info "IPv4 rules:"
log_info "--------------------"
iptables -L -v -n || log_warning "Failed to list IPv4 rules."
log_info "--------------------"
log_info "IPv6 rules:"
log_info "--------------------"
ip6tables -L -v -n 2>/dev/null || log_info "(IPv6 rules not listed, possibly disabled or ip6tables issue)"
log_info "--------------------"

log_info "Executing qBittorrent process..."
exec /bin/bash /etc/qbittorrent/start.sh

log_error_and_exit "Failed to execute /etc/qbittorrent/start.sh"