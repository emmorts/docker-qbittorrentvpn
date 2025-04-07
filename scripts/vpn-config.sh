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

detect_vpn_configuration_file() {
    if [[ "${VPN_TYPE}" == "openvpn" ]]; then
        log_info "Search for OpenVPN config file in /config/openvpn"
        log_info $(find /config/openvpn -maxdepth 1 \( -name "*.ovpn" -o -name "*.conf" \) ! -name "credentials.conf" -print -quit)
        # Search for both .ovpn and .conf files for OpenVPN
        export VPN_CONFIG=$(find /config/openvpn -maxdepth 1 \( -name "*.ovpn" -o -name "*.conf" \) ! -name "credentials.conf" -print -quit)
    else
        log_info "Search for WireGuard config file in /config/wireguard"
        log_info $(find /config/wireguard -maxdepth 1 -name "*.conf" -print -quit)
        export VPN_CONFIG=$(find /config/wireguard -maxdepth 1 -name "*.conf" -print -quit)
    fi

    if [[ ! -f "${VPN_CONFIG}" ]]; then
        if [[ "${VPN_TYPE}" == "openvpn" ]]; then
            log_error_and_exit "No OpenVPN configuration file found in /config/openvpn/. Please download one from your VPN provider and restart this container. Supported file extensions are '.ovpn' and '.conf'"
        else
            log_error_and_exit "No WireGuard config file found in /config/wireguard/. Please download one from your VPN provider and restart this container. Make sure the file extension is '.conf'"
        fi
    else
        log_info "'${VPN_TYPE}' configuration file found at '${VPN_CONFIG}'"

        if [[ "${VPN_TYPE}" == "openvpn" ]]; then
            setup_resolv_conf_script "${VPN_CONFIG}"
        fi
    fi

    validate_wireguard_config_name
}

setup_resolv_conf_script() {
    local vpn_config="$1"
    
    if grep -q "update-resolv-conf" "${vpn_config}"; then
        log_info "Configuration refers to update-resolv-conf script"
        
        if [[ -f "/config/openvpn/update-resolv-conf" ]]; then
            log_info "Found user-provided update-resolv-conf script, copying to /etc/openvpn/"
            cp "/config/openvpn/update-resolv-conf" "/etc/openvpn/"
            chmod +x "/etc/openvpn/update-resolv-conf"
        else
            log_warning "update-resolv-conf script not found in /config/openvpn/, creating a basic version"
            cat > "/etc/openvpn/update-resolv-conf" << 'EOF'
#!/bin/bash
# Simple script to update resolv.conf for OpenVPN
# This is version is created automatically

# Log function
log_msg() {
    echo "$1" | ts '%Y-%m-%d %H:%M:%.S'
}

log_msg "[INFO] update-resolv-conf script called with args: $*"

if [[ "$1" == "up" ]]; then
    for var in "${!foreign_option_*}"; do
        option="${!var}"
        
        if [[ "$option" == *"DOMAIN"* ]]; then
            domain=$(echo "$option" | cut -d" " -f3)
            log_msg "[INFO] Setting search domain: $domain"
            echo "search $domain" >> /etc/resolv.conf
        fi
        
        if [[ "$option" == *"DNS"* ]]; then
            dns=$(echo "$option" | cut -d" " -f3)
            log_msg "[INFO] Adding nameserver: $dns"
            echo "nameserver $dns" >> /etc/resolv.conf
        fi
    done
fi

exit 0
EOF
            chmod +x "/etc/openvpn/update-resolv-conf"
        fi
    fi
}

# Verify the WireGuard configuration file's name
validate_wireguard_config_name() {
    if [[ "${VPN_TYPE}" == "wireguard" && "${VPN_CONFIG}" != "/config/wireguard/wg0.conf" ]]; then
        log_error_and_exit "WireGuard configuration file name must be 'wg0.conf'. Rename ${VPN_CONFIG} to '/config/wireguard/wg0.conf'."
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
        grep -i "proto " "${VPN_CONFIG}" | head -n1 | awk '{print $2}'
        ;;
    "wireguard")
        echo "udp"
        ;;
    esac
}

configure_device_type() {
    local vpn_type="${1}"
    local vpn_config="${2}"

    validate_vpn_type "${vpn_type}"

    case "${vpn_type}" in
    "openvpn")
        local device_type=$(cat "${vpn_config}" | grep -P -o -m 1 '(?<=^dev\s)[^\r\n\d]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
        if [[ ! -z "${device_type}" ]]; then
            echo "${device_type}0"
        fi
        ;;
    "wireguard")
        echo "wg0"
        ;;
    esac
}
