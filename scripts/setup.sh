#!/bin/bash

# Ensure network dependencies are present
ensure_network_deps() {
    # Check if docker0 interface is present - indicating we're running in host mode.
    local network_check
    network_check=$(ifconfig | grep docker0 || true)

    if [[ -n "${network_check}" ]]; then
        log_error_and_exit "Detected network type 'Host'. This will cause major issues. Please switch back to 'Bridge' mode."
    fi
}

# Set up the VPN_ENABLED environment variable
configure_vpn_enabled() {
    # convert VPN_ENABLED to lowercase and remove leading/trailing whitespace
    export VPN_ENABLED=$(echo "${VPN_ENABLED,,}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

    # If VPN_ENABLED environment variable is not set, default to "yes"
    if [[ -z "${VPN_ENABLED}" ]]; then
        log_warning "VPN_ENABLED not defined (via -e VPN_ENABLED). Defaulting to 'yes'."
        export VPN_ENABLED="yes"
    else
        log_info "VPN_ENABLED set as '${VPN_ENABLED}'"
    fi
}

# Validate the input VPN_TYPE and set to lower case
configure_vpn_type() {
    if [[ -z ${VPN_TYPE} ]]; then
        log_info "VPN_TYPE not set, defaulting to 'openvpn'."
        export VPN_TYPE="openvpn"
    else
        export VPN_TYPE=$(echo "${VPN_TYPE}" | tr '[:upper:]' '[:lower:]')
    fi

    validate_vpn_type "${VPN_TYPE}"

    log_info "Using VPN_TYPE='${VPN_TYPE}'"
}

# Configure between legacy and nft version of iptables depending on the LEGACY_IPTABLES value
configure_iptables_mode() {
    export LEGACY_IPTABLES=$(echo "${LEGACY_IPTABLES,,}")

    log_info "LEGACY_IPTABLES is set to '${LEGACY_IPTABLES}'"

    if [[ "${LEGACY_IPTABLES}" =~ ${TRUE_REGEX} ]]; then
        log_info "Setting iptables to iptables (legacy)"
        update-alternatives --set iptables /usr/sbin/iptables-legacy
    else
        log_info "Not making any changes to iptables version"
    fi

    local -r iptables_version=$(iptables -V)
    log_info "The container is currently running ${iptables_version}."
}

# Configure DNS name servers
configure_dns_servers() {
    if [[ -z "${NAME_SERVERS}" ]]; then
		export NAME_SERVERS="1.1.1.1,8.8.8.8,1.0.0.1,8.8.4.4"

        log_info "No name servers provided in NAME_SERVERS, defaulting to Cloudflare and Google name servers"
    fi

    local -a dns_servers
    IFS=',' read -ra dns_servers <<<"${NAME_SERVERS// /}"

    for dns_server in "${dns_servers[@]}"; do
        log_info "Adding ${dns_server} to resolv.conf"
        echo "nameserver ${dns_server}" >>/etc/resolv.conf
    done
}

# Configure user permissions for the container
configure_user_rights() {
    if [[ -z "${PUID}" ]]; then
        log_info "PUID not defined. Defaulting to root user"
        export PUID="root"
    fi

    if [[ -z "${PGID}" ]]; then
        log_info "PGID not defined. Defaulting to root group"
        export PGID="root"
    fi
}

# Configure environment variable defaults
configure_env_vars() {
    local env_var_name="${1}"
    local default_value="${2}"
    local allow_empty="${3:-false}"

    local env_var_value=$(echo "${!env_var_name}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

    if [[ -n "${env_var_value}" ]]; then
        log_info "${env_var_name} defined as '${env_var_value}'"
    elif [[ -n "${default_value}" ]]; then
        log_warning "${env_var_name} not defined (via -e ${env_var_name}), defaulting to '${default_value}'"
        export "${env_var_name}=${default_value}"
    elif [[ "${allow_empty}" == "true" ]]; then
        log_info "${env_var_name} not defined (via -e ${env_var_name})"
        export "${env_var_name}="
    else
        log_error_and_exit "${env_var_name} not defined (via -e ${env_var_name}), exiting..."
    fi
}

# Ensure the VPN type is supported
validate_vpn_type() {
    local vpn_type=$1

    if [[ "${vpn_type}" != "openvpn" && "${vpn_type}" != "wireguard" ]]; then
        log_error_and_exit "${vpn_type} is not a valid VPN type. Please use either 'openvpn' or 'wireguard'."
    fi
}
