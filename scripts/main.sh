#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Source scripts using the dynamic base path
source "${SCRIPT_DIR}/constants.sh"
source "${SCRIPT_DIR}/setup.sh"
source "${SCRIPT_DIR}/vpn-config.sh"
source "${SCRIPT_DIR}/start-services.sh"

set -o errexit
set -o nounset
set -o pipefail

ensure_network_deps

configure_vpn_enabled
configure_iptables_mode
configure_dns_servers
configure_user_rights

if [[ "${VPN_ENABLED}" =~ ${TRUE_REGEX} ]]; then
    configure_vpn_type
    establish_config_directory "${VPN_TYPE}" "${PUID}" "${PGID}"
    detect_vpn_configuration_file
    add_credentials_to_openvpn_config "${VPN_TYPE}" "${VPN_CONFIG}" "${VPN_USERNAME}" "${VPN_PASSWORD}"

    convert_to_unix "${VPN_CONFIG}"
    vpn_remote_line=$(extract_vpn_remote_address "${VPN_TYPE}" "${VPN_CONFIG}")

    validate_key_value "VPN remote line" "${vpn_remote_line}" "${VPN_CONFIG}"

    export VPN_REMOTE="$(configure_remote "${VPN_TYPE}" "${vpn_remote_line}")"
    validate_key_value "VPN_REMOTE" "${VPN_REMOTE}" "${VPN_CONFIG}"

    export VPN_PORT="$(configure_port "${VPN_TYPE}" "${vpn_remote_line}")"
    validate_key_value "VPN_PORT" "${VPN_PORT}" "${VPN_CONFIG}"

    export VPN_PROTOCOL="$(configure_protocol "${VPN_TYPE}")"
    validate_key_value "VPN_PROTOCOL" "${VPN_PROTOCOL}" "${VPN_CONFIG}"

    export VPN_DEVICE_TYPE="$(configure_device_type "${VPN_TYPE}")"
    validate_key_value "VPN_DEVICE_TYPE" "${VPN_DEVICE_TYPE}" "${VPN_CONFIG}"

    configure_env_vars "LAN_NETWORK" ""
    configure_env_vars "NAME_SERVERS" "1.1.1.1,8.8.8.8,1.0.0.1,8.8.4.4"

    if [[ "${VPN_TYPE}" == "openvpn" ]]; then
        configure_env_vars "VPN_OPTIONS" ""
    fi

    start_vpn "${VPN_TYPE}" "${VPN_CONFIG}"
else
    display_vpn_disabled_warning
fi

start_qbittorrent "${VPN_ENABLED}"
