#!/bin/bash
# Forked from binhex's OpenVPN dockers
set -e

# function to handle exit
exit_script() {
    echo "[ERROR] $1" | ts '%Y-%m-%d %H:%M:%.S'
    # Sleep so it won't 'spam restart'
    sleep 10
    exit 1
}

# function to check for presence of network interface docker0
check_network_dependencies() {
  check_network=$(ifconfig | grep docker0 || true)
# if network interface docker0 is present then we are running in host mode and thus must exit
  if [[ ! -z "${check_network}" ]]; then
    exit_script "Network type detected as 'Host', this will cause major issues, please stop the container and switch back to 'Bridge' mode"
  fi
}

# function to chek if VPN is enabled
check_vpn_enabled() {
	export VPN_ENABLED=$(echo "${VPN_ENABLED,,}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_ENABLED}" ]]; then
		echo "[INFO] VPN_ENABLED defined as '${VPN_ENABLED}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[WARNING] VPN_ENABLED not defined,(via -e VPN_ENABLED), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
		export VPN_ENABLED="yes"
	fi
}

# function to check if Linux Kernel's iptables is in legacy mode
check_iptables_mode() {
  export LEGACY_IPTABLES=$(echo "${LEGACY_IPTABLES,,}")
  echo "[INFO] LEGACY_IPTABLES is set to '${LEGACY_IPTABLES}'" | ts '%Y-%m-%d %H:%M:%.S'
  if [[ $LEGACY_IPTABLES == "1" || $LEGACY_IPTABLES == "true" || $LEGACY_IPTABLES == "yes" ]]; then
    echo "[INFO] Setting iptables to iptables (legacy)" | ts '%Y-%m-%d %H:%M:%.S'
    update-alternatives --set iptables /usr/sbin/iptables-legacy
  else
    echo "[INFO] Not making any changes to iptables version" | ts '%Y-%m-%d %H:%M:%.S'
  fi
  iptables_version=$(iptables -V)
  echo "[INFO] The container is currently running ${iptables_version}."  | ts '%Y-%m-%d %H:%M:%.S'
}

check_vpn_type() {
    # Check if VPN_TYPE is set.
    if [[ -z "${VPN_TYPE}" ]]; then
        echo "[WARNING] VPN_TYPE not set, defaulting to OpenVPN." | ts '%Y-%m-%d %H:%M:%.S'
        export VPN_TYPE="openvpn"
    else
        echo "[INFO] VPN_TYPE defined as '${VPN_TYPE}'" | ts '%Y-%m-%d %H:%M:%.S'
    fi

    if [[ "${VPN_TYPE}" != "openvpn" && "${VPN_TYPE}" != "wireguard" ]]; then
        echo "[WARNING] VPN_TYPE not set, as 'wireguard' or 'openvpn', defaulting to OpenVPN." | ts '%Y-%m-%d %H:%M:%.S'
        export VPN_TYPE="openvpn"
    fi
}

create_and_set_permissions_for_config_dir() {
    # Create the directory to store OpenVPN or WireGuard config files
    mkdir -p /config/${VPN_TYPE}
    # Set permmissions and owner for files in /config/openvpn or /config/wireguard directory
    set +e
    chown -R "${PUID}":"${PGID}" "/config/${VPN_TYPE}" &> /dev/null
    exit_code_chown=$?
    chmod -R 775 "/config/${VPN_TYPE}" &> /dev/null
    exit_code_chmod=$?
    set -e
    if (( ${exit_code_chown} != 0 || ${exit_code_chmod} != 0 )); then
        echo "[WARNING] Unable to chown/chmod /config/${VPN_TYPE}/, assuming SMB mountpoint" | ts '%Y-%m-%d %H:%M:%.S'
    fi
}

search_for_vpn_config_files() {
    # Wildcard search for openvpn config files (match on first result)
    if [[ "${VPN_TYPE}" == "openvpn" ]]; then
        export VPN_CONFIG=$(find /config/openvpn -maxdepth 1 -name "*.ovpn" -print -quit)
    else
        export VPN_CONFIG=$(find /config/wireguard -maxdepth 1 -name "*.conf" -print -quit)
    fi
}

check_if_vpn_files_exist() {
    # If ovpn file not found in /config/openvpn or /config/wireguard then exit
    if [[ -z "${VPN_CONFIG}" ]]; then
        if [[ "${VPN_TYPE}" == "openvpn" ]]; then
            exit_script "No OpenVPN config file found in /config/openvpn/. Please download one from your VPN provider and restart this container. Make sure the file extension is '.ovpn'"
        else
            exit_script "No WireGuard config file found in /config/wireguard/. Please download one from your VPN provider and restart this container. Make sure the file extension is '.conf'"
        fi
    fi
}

check_and_log_vpn_config_file() {
    if [[ "${VPN_TYPE}" == "openvpn" ]]; then
        echo "[INFO] OpenVPN config file is found at ${VPN_CONFIG}" | ts '%Y-%m-%d %H:%M:%.S'
    else
        echo "[INFO] WireGuard config file is found at ${VPN_CONFIG}" | ts '%Y-%m-%d %H:%M:%.S'
        if [[ "${VPN_CONFIG}" != "/config/wireguard/wg0.conf" ]]; then
            exit_script "WireGuard config filename is not 'wg0.conf'. Rename ${VPN_CONFIG} to 'wg0.conf"
        fi
    fi
}

configure_vpn() {
    local VPN_TYPE=$1
    local VPN_CONFIG=$2
    local VPN_USERNAME=$3
    local VPN_PASSWORD=$4

    # Read username and password env vars and put them in credentials.conf, then add ovpn config for credentials file
    if [[ "${VPN_TYPE}" == "openvpn" ]]; then
        if [[ ! -z "${VPN_USERNAME}" ]] && [[ ! -z "${VPN_PASSWORD}" ]]; then
            if [[ ! -e /config/openvpn/credentials.conf ]]; then
                touch /config/openvpn/credentials.conf
            fi

            echo "${VPN_USERNAME}" > /config/openvpn/credentials.conf
            echo "${VPN_PASSWORD}" >> /config/openvpn/credentials.conf

            # Replace line with one that points to credentials.conf
            auth_cred_exist=$(cat "${VPN_CONFIG}" | grep -m 1 'auth-user-pass')
            if [[ ! -z "${auth_cred_exist}" ]]; then
                # Get line number of auth-user-pass
                LINE_NUM=$(grep -Fn -m 1 'auth-user-pass' "${VPN_CONFIG}" | cut -d: -f 1)
                sed -i "${LINE_NUM}s/.*/auth-user-pass credentials.conf/" "${VPN_CONFIG}"
            else
                sed -i "1s/.*/auth-user-pass credentials.conf/" "${VPN_CONFIG}"
            fi
        fi
    fi
}

parse_config() {
    local vpn_type="${1}"
    local vpn_config="${2}"

   case "${vpn_type}" in
        "openvpn")
            grep -P -o -m 1 '(?<=^remote\s)[^\n\r]+' "${vpn_config}"
            ;;
        *)
            cat "${vpn_config}" | grep -P -o -m 1 '(?<=^Endpoint)(\s{0,})[^\n\r]+' | sed -e 's~^[=\ ]*~~'
            ;;
    esac
}

get_value() {
    local regex="${1}"
    local line="${2}"
    echo "${line}" | grep -P -o -m 1 "${regex}"
}

convert_to_unix() {
    local file="${1}"
    dos2unix "${file}" 1> /dev/null
}

print_info() {
    local key="${1}"
    local value="${2}"
    if [[ ! -z "${value}" ]]; then
        echo "[INFO] ${key} defined as '${value}'" | ts '%Y-%m-%d %H:%M:%.S'
    else
        exit_script "${key} not found in ${VPN_CONFIG}, exiting..."
    fi
}

configure_protocol() {
    local vpn_type="${1}"
    
    if [[ "${vpn_type}" == "openvpn" ]]; then
        echo "udp|tcp-client|tcp$"
    else
        echo "udp"
    fi
}

configure_device_type() {
    local vpn_type="${1}"
    
    if [[ "${vpn_type}" == "openvpn" ]]; then
        grep -P -o -m 1 '(?<=^dev\s)[^\r\n\d]+'
    else
        echo "wg0"
    fi
}

configure_env_vars() {
    local name="${1}"
    local default="${2}"
    
    local value=$(echo "${!name}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
    
    if [[ ! -z "${value}" ]]; then
        echo "[INFO] ${name} defined as '${value}'" | ts '%Y-%m-%d %H:%M:%.S'
    elif [[ ! -z "${default}" ]]; then
        echo "[WARNING] ${name} not defined (via -e ${name}), defaulting to '${default}'" | ts '%Y-%m-%d %H:%M:%.S'
        export "${name}=${default}"
    else
        exit_script "${name} not defined (via -e ${name}), exiting..."
    fi
}

add_to_resolv_conf() {
    local name_server_list
    IFS=',' read -ra name_server_list <<< "${NAME_SERVERS}"
    for name_server_item in "${name_server_list[@]}"; do
        # strip whitespace from start and end of lan_network_item
        name_server_item=$(echo "${name_server_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
        
        echo "[INFO] Adding ${name_server_item} to resolv.conf" | ts '%Y-%m-%d %H:%M:%.S'
        echo "nameserver ${name_server_item}" >> /etc/resolv.conf
    done
}

set_default_user_and_group() {
    if [[ -z "${PUID}" ]]; then
        echo "[INFO] PUID not defined. Defaulting to root user" | ts '%Y-%m-%d %H:%M:%.S'
        export PUID="root"
    fi

    if [[ -z "${PGID}" ]]; then
        echo "[INFO] PGID not defined. Defaulting to root group" | ts '%Y-%m-%d %H:%M:%.S'
        export PGID="root"
    fi
}

setup_VPN() {
    if [[ "${VPN_TYPE}" == "openvpn" ]]; then
        echo "[INFO] Starting OpenVPN..." | ts '%Y-%m-%d %H:%M:%.S'
        cd /config/openvpn
        exec openvpn --pull-filter ignore route-ipv6 --pull-filter ignore ifconfig-ipv6 --config "${VPN_CONFIG}" &
    else
        echo "[INFO] Starting WireGuard..." | ts '%Y-%m-%d %H:%M:%.S'
        cd /config/wireguard
        [ $(ip link | grep -q `basename -s .conf $VPN_CONFIG`) ] && \
            { wg-quick down $VPN_CONFIG || echo "WireGuard is down already" | ts '%Y-%m-%d %H:%M:%.S'; sleep 0.5; }
        wg-quick up $VPN_CONFIG
    fi
    
    exec /bin/bash /etc/qbittorrent/iptables.sh
}

display_warning_VPN_disabled() {
    echo "[WARNIG] @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@" | ts '%Y-%m-%d %H:%M:%.S'
    echo "[WARNIG] THE CONTAINER IS RUNNING WITH VPN DISABLED" | ts '%Y-%m-%d %H:%M:%.S'
    echo "[WARNIG] PLEASE MAKE SURE VPN_ENABLED IS SET TO 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
    echo "[WARNIG] IF THIS IS INTENTIONAL, YOU CAN IGNORE THIS" | ts '%Y-%m-%d %H:%M:%.S'
    echo "[WARNIG] @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@" | ts '%Y-%m-%d %H:%M:%.S'
    
    exec /bin/bash /etc/qbittorrent/start.sh
}

check_network_dependencies
check_vpn_enabled
check_iptables_mode


if [[ $VPN_ENABLED == "1" || $VPN_ENABLED == "true" || $VPN_ENABLED == "yes" ]]; then
	check_vpn_type
	create_and_set_permissions_for_config_dir
	search_for_vpn_config_files
	check_if_vpn_files_exist
	check_and_log_vpn_config_file

	configure_vpn "${VPN_TYPE}" "${VPN_CONFIG}" "${VPN_USERNAME}" "${VPN_PASSWORD}"
	convert_to_unix "${VPN_CONFIG}"
	vpn_remote_line=$(parse_config "${VPN_TYPE}" "${VPN_CONFIG}")

	print_info "VPN remote line" "${vpn_remote_line}"

	export VPN_REMOTE=$(get_value '^[^\s\r\n]+' "${vpn_remote_line}")
	print_info "VPN_REMOTE" "${VPN_REMOTE}"

	export VPN_PORT=$(get_value '(?<=\s)\d{2,5}(?=\s)?+' "${vpn_remote_line}")
	print_info "VPN_PORT" "${VPN_PORT}"

	export VPN_PROTOCOL="$(configure_protocol "${VPN_TYPE}")"
	print_info "VPN_PROTOCOL" "${VPN_PROTOCOL}"

	export VPN_DEVICE_TYPE="$(configure_device_type "${VPN_TYPE}")"
	print_info "VPN_DEVICE_TYPE" "${VPN_DEVICE_TYPE}"

	configure_env_vars "LAN_NETWORK" ""
	configure_env_vars "NAME_SERVERS" "1.1.1.1,8.8.8.8,1.0.0.1,8.8.4.4"

	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		configure_env_vars "VPN_OPTIONS" ""
	fi

else
	echo "[WARNING] !!IMPORTANT!! You have set the VPN to disabled, your connection will NOT be secure!" | ts '%Y-%m-%d %H:%M:%.S'
fi

add_to_resolv_conf
set_default_user_and_group
if [[ $VPN_ENABLED == "1" || $VPN_ENABLED == "true" || $VPN_ENABLED == "yes" ]]; then
	setup_VPN
else
	display_warning_VPN_disabled
fi