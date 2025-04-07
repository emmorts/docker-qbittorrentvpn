#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

# Constants
readonly LOG_DATE_FORMAT='%Y-%m-%d %H:%M:%.S'

# Logging Functions
log_error_and_exit() {
  local -r message="$1"
  echo "[ERROR] ${message}" | ts "${LOG_DATE_FORMAT}"
  sleep 10
  exit 1
}

log_warning() {
  local -r message="$1"
  echo "[WARNING] ${message}" | ts "${LOG_DATE_FORMAT}"
}

log_info() {
  local -r message="$1"
  echo "[INFO] ${message}" | ts "${LOG_DATE_FORMAT}"
}

# ---

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

# Configure between legacy and nft version of iptables depending on the LEGACY_IPTABLES value
configure_iptables_mode() {
  export LEGACY_IPTABLES=$(echo "${LEGACY_IPTABLES,,}")

  log_info "LEGACY_IPTABLES is set to '${LEGACY_IPTABLES}'"

  if [[ "${LEGACY_IPTABLES}" =~ ^(1|true|yes)$ ]]; then
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
  local -a name_server_list
  IFS=',' read -ra name_server_list <<<"${NAME_SERVERS// /}"

  if [[ -z "${name_server_list[*]}" ]]; then
    log_error_and_exit "No name servers provided in NAME_SERVERS. Exiting..."
  fi
  
  for name_server in "${name_server_list[@]}"; do
    log_info "Adding ${name_server} to resolv.conf"
    echo "nameserver ${name_server}" >>/etc/resolv.conf
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

setup_vpn_type() {
  if [[ -z "${VPN_TYPE}" ]]; then
    log_warning "VPN_TYPE not set, defaulting to OpenVPN."
    VPN_TYPE="openvpn"
  fi

  VPN_TYPE=$(echo "${VPN_TYPE}" | tr '[:upper:]' '[:lower:]')

  if [[ "${VPN_TYPE}" != "openvpn" && "${VPN_TYPE}" != "wireguard" ]]; then
    log_error_and_exit "Invalid VPN_TYPE. It should be either 'wireguard' or 'openvpn'. Exiting..."
  fi

  log_info "VPN_TYPE defined as '${VPN_TYPE}'"
  export VPN_TYPE
}

validate_vpn_type() {
  local vpn_type=$1

  if [[ "${vpn_type}" != "openvpn" && "${vpn_type}" != "wireguard" ]]; then
    log_error_and_exit "${vpn_type} is not a valid VPN type. Please use either 'openvpn' or 'wireguard'."
  fi
}

setup_config_directory() {
  local -r config_dir="/config/${VPN_TYPE}"

  # Create the directory to store OpenVPN or WireGuard config files
  mkdir -p "${config_dir}"

  # Set permissions and owner for files in /config/openvpn or /config/wireguard directory
  if chown -R "${PUID}":"${PGID}" "${config_dir}" &>/dev/null; then
    log_info "Changed ownership of ${config_dir} to ${PUID}:${PGID}"
  else
    log_warning "Failed to change the ownership of ${config_dir}. Assuming SMB mount point or lack of permissions."
  fi

  if chmod -R 775 "${config_dir}" &>/dev/null; then
    log_info "Changed permissions of ${config_dir} to 775"
  else
    log_warning "Failed to change the permissions of ${config_dir}. Assuming SMB mount point or lack of permissions."
  fi
}

search_for_vpn_config_files() {
  # Wildcard search for openvpn config files (match on first result)
  if [[ "${VPN_TYPE}" == "openvpn" ]]; then
    export VPN_CONFIG=$(find /config/openvpn -maxdepth 1 \( -name "*.ovpn" -o -name "*.conf" \) -print -quit)
  else
    export VPN_CONFIG=$(find /config/wireguard -maxdepth 1 -name "*.conf" -print -quit)
  fi
}

check_if_vpn_files_exist() {
  # If config file not found in /config/openvpn or /config/wireguard then exit
  if [[ -z "${VPN_CONFIG}" ]]; then
    if [[ "${VPN_TYPE}" == "openvpn" ]]; then
      log_error_and_exit "No OpenVPN config file found in /config/openvpn/. Please download one from your VPN provider and restart this container. Supported file extensions are '.ovpn' and '.conf'"
    else
      log_error_and_exit "No WireGuard config file found in /config/wireguard/. Please download one from your VPN provider and restart this container. Make sure the file extension is '.conf'"
    fi
  fi
}

check_and_log_vpn_config_file() {
  if [[ "${VPN_TYPE}" == "openvpn" ]]; then
    log_info "OpenVPN config file is found at ${VPN_CONFIG}"
  else
    log_info "WireGuard config file is found at ${VPN_CONFIG}"
    if [[ "${VPN_CONFIG}" != "/config/wireguard/wg0.conf" ]]; then
      log_error_and_exit "WireGuard config filename is not 'wg0.conf'. Rename ${VPN_CONFIG} to 'wg0.conf"
    fi
  fi
}

configure_vpn() {
  local vpn_type="$1"
  local vpn_config="$2"
  local vpn_username="$3"
  local vpn_password="$4"

  if [[ "${vpn_type,,}" == "openvpn" && -n "${vpn_username}" && -n "${vpn_password}" ]]; then
    local credentials_path="/config/openvpn/credentials.conf"

    if [[ ! -e "${credentials_path}" ]]; then
      touch "${credentials_path}"
    fi

    echo -e "${vpn_username}\n${vpn_password}" >"${credentials_path}"

    if grep -q -F -- 'auth-user-pass' "${vpn_config}"; then
      sed -i "/auth-user-pass/c\auth-user-pass ${credentials_path}" "${vpn_config}"
    else
      echo -e "auth-user-pass ${credentials_path}\n$(cat "${vpn_config}")" >"${vpn_config}"
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

convert_to_unix() {
  local file="${1}"
  dos2unix "${file}" 1>/dev/null
}

validate_and_log_key_value() {
  local key="${1}"
  local value="${2}"
  if [[ -n "${value}" ]]; then
    log_info "${key} defined as '${value}'"
  else
    log_error_and_exit "${key} not found in ${VPN_CONFIG}, exiting..."
  fi
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

configure_env_vars() {
  local name="${1}"
  local default="${2}"

  local value=$(echo "${!name}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

  if [[ ! -z "${value}" ]]; then
    log_info "${name} defined as '${value}'"
  elif [[ ! -z "${default}" ]]; then
    log_warning "${name} not defined (via -e ${name}), defaulting to '${default}'"
    export "${name}=${default}"
  else
    log_error_and_exit "${name} not defined (via -e ${name}), exiting..."
  fi
}

start_open_vpn() {
  log_info "Starting OpenVPN..."

  exec openvpn --pull-filter ignore route-ipv6 --pull-filter ignore ifconfig-ipv6 --config "/config/openvpn/${VPN_CONFIG}" &
}

start_wire_guard() {
  log_info "Starting WireGuard..."

  local conf_name=$(basename -s .conf "${VPN_CONFIG}")
  if ip link | grep -q "${conf_name}"; then
    wg-quick down "${VPN_CONFIG}" || log_info "WireGuard is down already"
    sleep 0.5
  fi

  wg-quick up "/config/wireguard/${VPN_CONFIG}"
}

start_vpn() {
  if [[ "${VPN_TYPE}" == "openvpn" ]]; then
    start_open_vpn
  else
    start_wire_guard
  fi
}

display_warning_vpn_disabled() {
  log_warning "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
  log_warning "THE CONTAINER IS RUNNING WITH VPN DISABLED"
  log_warning "PLEASE MAKE SURE VPN_ENABLED IS SET TO 'yes'"
  log_warning "IF THIS IS INTENTIONAL, YOU CAN IGNORE THIS"
  log_warning "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
}

start_qbittorrent() {
  if [[ "${VPN_ENABLED}" =~ ^(1|true|yes)$ ]]; then
    exec /bin/bash /etc/qbittorrent/iptables.sh
  else
    exec /bin/bash /etc/qbittorrent/start.sh
  fi
}

ensure_network_deps
configure_vpn_enabled
configure_iptables_mode
configure_dns_servers
configure_user_rights

if [[ "${VPN_ENABLED}" =~ ^(1|true|yes)$ ]]; then
  setup_vpn_type
  setup_config_directory
  search_for_vpn_config_files
  check_if_vpn_files_exist
  check_and_log_vpn_config_file

  configure_vpn "${VPN_TYPE}" "${VPN_CONFIG}" "${VPN_USERNAME}" "${VPN_PASSWORD}"
  convert_to_unix "${VPN_CONFIG}"

  vpn_remote_line=$(extract_vpn_remote_address "${VPN_TYPE}" "${VPN_CONFIG}")

  validate_and_log_key_value "VPN remote line" "${vpn_remote_line}"

  export VPN_REMOTE="$(configure_remote "${VPN_TYPE}" "${vpn_remote_line}")"
  validate_and_log_key_value "VPN_REMOTE" "${VPN_REMOTE}"

  export VPN_PORT="$(configure_port "${VPN_TYPE}" "${vpn_remote_line}")"
  validate_and_log_key_value "VPN_PORT" "${VPN_PORT}"

  export VPN_PROTOCOL="$(configure_protocol "${VPN_TYPE}")"
  validate_and_log_key_value "VPN_PROTOCOL" "${VPN_PROTOCOL}"

  export VPN_DEVICE_TYPE="$(configure_device_type "${VPN_TYPE}")"
  validate_and_log_key_value "VPN_DEVICE_TYPE" "${VPN_DEVICE_TYPE}"

  configure_env_vars "LAN_NETWORK" ""
  configure_env_vars "NAME_SERVERS" "1.1.1.1,8.8.8.8,1.0.0.1,8.8.4.4"

  if [[ "${VPN_TYPE}" == "openvpn" ]]; then
    configure_env_vars "VPN_OPTIONS" ""
  fi

  start_vpn
else
  display_warning_vpn_disabled
fi

start_qbittorrent
