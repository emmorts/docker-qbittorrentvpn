#!/bin/bash

# Create and configure VPN config directory with correct permissions
establish_config_directory() {
    local vpn_type="${1}"
    local puid="${2}"
    local pgid="${3}"

    local -r config_dir="/config/${vpn_type}"

    mkdir -p "${config_dir}"

    if chown -R "${puid}":"${pgid}" "${config_dir}" &>/dev/null; then
        log_info "Changed ownership of ${config_dir} to ${puid}:${pgid}"
    else
        log_warning "Failed to change the ownership of ${config_dir}. Assuming SMB mount point or lack of permissions."
    fi

    if chmod -R 775 "${config_dir}" &>/dev/null; then
        log_info "Changed permissions of ${config_dir} to 775"
    else
        log_warning "Failed to change the permissions of ${config_dir}. Assuming SMB mount point or lack of permissions."
    fi
}

# Find the VPN configuration file
detect_vpn_configuration_file() {
    if [[ "${VPN_TYPE}" == "openvpn" ]]; then
        export VPN_CONFIG=$(find /config/openvpn -maxdepth 1 -name "*.ovpn" -print -quit)
    else
        export VPN_CONFIG=$(find /config/wireguard -maxdepth 1 -name "*.conf" -print -quit)
    fi

    if [[ ! -f "${VPN_CONFIG}" ]]; then
        error_exit "No '${VPN_TYPE}' configuration file found in /config/${VPN_TYPE}/. Please download one from your VPN provider and restart this container."
    else
        echo_log "'${VPN_TYPE}' configuration file found at '${VPN_CONFIG}'"
    fi

    validate_wireguard_config_name
}

# Verify the WireGuard configuration file's name
validate_wireguard_config_name() {
    if [[ "${VPN_TYPE}" == "wireguard" && "${VPN_CONFIG}" != "/config/wireguard/wg0.conf" ]]; then
        error_exit "WireGuard configuration file name must be 'wg0.conf'. Rename ${VPN_CONFIG} to '/config/wireguard/wg0.conf'."
    fi
}

# Create an OpenVPN configuration file with credentials
add_credentials_to_openvpn_config() {
    local vpn_type="$1"
    local vpn_config="$2"
    local vpn_username="$3"
    local vpn_password="$4"

    if [[ "${vpn_type,,}" == "openvpn" && -n "${vpn_username}" && -n "${vpn_password}" ]]; then
        local credentials_path="/config/openvpn/credentials.conf"
        echo -e "${vpn_username}\n${vpn_password}" >"${credentials_path}"
        if grep -q -F 'auth-user-pass' "${vpn_config}"; then
            sed -i "/auth-user-pass/c\auth-user-pass ${credentials_path}" "${vpn_config}"
        else
            echo -e "auth-user-pass ${credentials_path}\n$(cat ${vpn_config})" >"${vpn_config}"
        fi
    fi
}

extract_vpn_remote_address() {
    local vpn_type="${1,,}"
    local vpn_config="${2}"

    validate_vpn_type "${vpn_type}"

    case "${vpn_type}" in
    "openvpn")
        grep -P -o -m 1 '(?<=^remote\s)[^\n\r]+' "${vpn_config}"
        ;;
    "wireguard")
        grep -P -o -m 1 '(?<=^Endpoint)(\s{0,})[^\n\r]+' "${vpn_config}" | sed -e 's~^[=\ ]*~~'
        ;;
    esac
}

configure_remote() {
    local vpn_type="${1}"
    local vpn_remote_line="${2}"

    validate_vpn_type "${vpn_type}"

    case "${vpn_type}" in
    "openvpn")
        echo "${vpn_remote_line}" | grep -P -o -m 1 '^[^\s\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~'
        ;;
    "wireguard")
        echo "${vpn_remote_line}" | grep -P -o -m 1 '^[^:\r\n]+'
        ;;
    esac
}

configure_port() {
    local vpn_type="${1}"
    local vpn_remote_line="${2}"

    validate_vpn_type "${vpn_type}"

    case "${vpn_type}" in
    "openvpn")
        echo "${vpn_remote_line}" | grep -P -o -m 1 '(?<=\s)\d{2,5}(?=\s)?+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~'
        ;;
    "wireguard")
        echo "${vpn_remote_line}" | grep -P -o -m 1 '(?<=:)\d{2,5}(?=:)?+'
        ;;
    esac
}

configure_protocol() {
    local vpn_type="${1}"

    validate_vpn_type "${vpn_type}"

    case "${vpn_type}" in
    "openvpn")
        echo "udp|tcp-client|tcp$"
        ;;
    "wireguard")
        echo "udp"
        ;;
    esac
}

configure_device_type() {
    local vpn_type="${1}"

    validate_vpn_type "${vpn_type}"

    case "${vpn_type}" in
    "openvpn")
        grep -P -o -m 1 '(?<=^dev\s)[^\r\n\d]+'
        ;;
    "wireguard")
        echo "wg0"
        ;;
    esac
}
