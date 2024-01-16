#!/bin/bash

readonly SLEEP_DELAY='0.5'

start_open_vpn() {
    local vpn_config_path="${1}"

    log_info "Starting OpenVPN..."
    exec openvpn --pull-filter ignore route-ipv6 --pull-filter ignore ifconfig-ipv6 --config "/config/openvpn/${vpn_config_path}" &
}

start_wire_guard() {
    local vpn_config_path="${1}"

    log_info "Starting WireGuard..."

    local conf_name
    conf_name=$(basename -s .conf "${vpn_config_path}")

    if (($(ip link | grep -c "${conf_name}") > 0)); then
        wg-quick down "${vpn_config_path}" || log_info "WireGuard is down already"
        sleep "${SLEEP_DELAY}"
    fi
    wg-quick up "${vpn_config_path}"
}

start_vpn() {
    local vpn_type="${1}"
    local vpn_config_path="${2}"

    case "${vpn_type}" in
    openvpn)
        start_open_vpn "${vpn_config_path}"
        ;;
    wireguard)
        start_wire_guard "${vpn_config_path}"
        ;;
    *)
        log_error_and_exit "Invalid VPN_TYPE: ${VPN_TYPE}"
        ;;
    esac
}

display_vpn_disabled_warning() {
    log_warning "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    log_warning "THE CONTAINER IS RUNNING WITH VPN DISABLED"
    log_warning "PLEASE MAKE SURE VPN_ENABLED IS SET TO 'yes'"
    log_warning "IF THIS IS INTENTIONAL, YOU CAN IGNORE THIS"
    log_warning "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
}

start_qbittorrent() {
    local vpn_enabled="${1}"

    if [[ "${vpn_enabled}" =~ ${TRUE_REGEX} ]]; then
        log_info "Starting qBitTorrent with VPN enabled..."

        exec /bin/bash /etc/qbittorrent/iptables.sh
    else
        log_info "Starting qBitTorrent without VPN..."

        exec /bin/bash /etc/qbittorrent/start.sh
    fi
}
