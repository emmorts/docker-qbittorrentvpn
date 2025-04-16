#!/bin/bash

readonly SLEEP_DELAY='0.5'
readonly PROCESS_CHECK_DELAY='2'

start_open_vpn() {
    local -r vpn_config_path="${1}"
    local -r vpn_config_dir=$(dirname "${vpn_config_path}")
    local -r vpn_config_file=$(basename "${vpn_config_path}")

    local -r openvpn_log_file="/config/openvpn/openvpn.log" # stdout
    local -r openvpn_stderr_tmp="/tmp/openvpn_stderr.log"   # stderr

    local openvpn_pid

    log_info "Attempting to start OpenVPN process in background..."
    log_info "Using config: ${vpn_config_path}"
    log_info "OpenVPN detailed logs will be written to: ${openvpn_log_file}"

    if ! mkdir -p "$(dirname "${openvpn_log_file}")"; then
        log_warning "Could not create log directory $(dirname "${openvpn_log_file}"). Logging might fail."
    fi

    touch "${openvpn_log_file}" || log_warning "Could not touch log file ${openvpn_log_file}"
    
    rm -f "${openvpn_stderr_tmp}"
    
    # change to the directory containing the config file so relative paths (certs, etc.) work
    cd "${vpn_config_dir}" || { log_warning "Failed to change directory to ${vpn_config_dir}. Relative paths in config might fail."; return 1; }
    
    openvpn --pull-filter ignore route-ipv6 --pull-filter ignore ifconfig-ipv6 --config "${vpn_config_file}" 1>> "${openvpn_log_file}" 2> "${openvpn_stderr_tmp}" &
    openvpn_pid=$!

    if [[ -z "${openvpn_pid}" ]]; then
        log_warning "Failed to get PID for OpenVPN process launch."
        # check if the temporary stderr file captured anything during the failed launch
        if [[ -s "${openvpn_stderr_tmp}" ]]; then
             log_warning "Error output captured during launch attempt:"
             cat "${openvpn_stderr_tmp}" | while IFS= read -r line; do log_warning "  | ${line}"; done
             cat "${openvpn_stderr_tmp}" >> "${openvpn_log_file}"
             rm -f "${openvpn_stderr_tmp}"
        else
            log_warning "No specific error output captured."
        fi
        cd - > /dev/null
        return 1
    fi


    log_info "OpenVPN process launched with PID ${openvpn_pid}. Waiting ${PROCESS_CHECK_DELAY}s to check status..."
    sleep "${PROCESS_CHECK_DELAY}"

    if kill -0 "${openvpn_pid}" 2>/dev/null; then
        log_info "OpenVPN process (PID ${openvpn_pid}) appears to be running successfully."
        log_info "For detailed OpenVPN status, check the log file: ${openvpn_log_file}"
        if [[ -f "${openvpn_stderr_tmp}" ]]; then
            cat "${openvpn_stderr_tmp}" >> "${openvpn_log_file}"
            rm -f "${openvpn_stderr_tmp}"
        fi
        cd - > /dev/null
        return 0
    else
        log_warning "OpenVPN process (PID ${openvpn_pid}) failed to start correctly or exited prematurely."
        if [[ -s "${openvpn_stderr_tmp}" ]]; then
             log_warning "Error output captured from OpenVPN:"
             cat "${openvpn_stderr_tmp}" | while IFS= read -r line; do log_warning "  | ${line}"; done
             cat "${openvpn_stderr_tmp}" >> "${openvpn_log_file}"
             rm -f "${openvpn_stderr_tmp}"
        else
             log_warning "No specific error output was captured in temporary stderr file."
             log_warning "Check the main OpenVPN log file for details: ${openvpn_log_file}"
        fi
        cd - > /dev/null
        return 1
    fi
}

start_wire_guard() {
    local -r vpn_config_path="${1}"
    local conf_name

    # Extract config name (e.g., wg0) from the path wg0.conf -> wg0
    conf_name=$(basename -s .conf "${vpn_config_path}")
    if [[ -z "${conf_name}" ]]; then
        log_warning "Could not determine WireGuard interface name from path ${vpn_config_path}."
        return 1
    fi

    log_info "Attempting to start WireGuard interface ${conf_name}..."
    log_info "Using config: ${vpn_config_path}"

    # check if the interface exists and try to bring it down first
    # wg-quick down is idempotent, but checking first avoids unnecessary commands/logs
    if ip link show "${conf_name}" > /dev/null 2>&1; then
        log_info "Interface ${conf_name} exists, attempting wg-quick down..."
        # failure here is not critical, might already be down or have issues
        wg-quick down "${vpn_config_path}" || log_info "wg-quick down exited non-zero (interface might be down or config issues)."
    else
        log_info "Interface ${conf_name} does not exist yet."
    fi

    log_info "Running wg-quick up ${conf_name}..."
    if wg-quick up "${vpn_config_path}"; then
        log_info "WireGuard interface ${conf_name} started successfully via wg-quick."
        return 0
    else
        local exit_code=$?
        log_warning "wg-quick up for ${conf_name} failed with exit code ${exit_code}."
        log_warning "Check WireGuard/system logs (e.g., 'journalctl -u wg-quick@${conf_name}' on host if applicable, or container logs)."
        return 1
    fi
}

start_vpn() {
    local -r vpn_type="${1}"
    local -r vpn_config_path="${2}"
    local vpn_started_successfully=false

    log_info "Initiating VPN startup sequence for type: ${vpn_type}"

    case "${vpn_type}" in
    openvpn)
        if start_open_vpn "${vpn_config_path}"; then
            vpn_started_successfully=true
        fi
        ;;
    wireguard)
        if start_wire_guard "${vpn_config_path}"; then
            vpn_started_successfully=true
        fi
        ;;
    *)
        log_error_and_exit "Invalid VPN_TYPE '${vpn_type}' passed to start_vpn function."
        ;;
    esac

    if [[ "${vpn_started_successfully}" == "true" ]]; then
        log_info "VPN startup sequence appears successful for ${vpn_type}."
        # allow some time for the tunnel interface to potentially appear/stabilize before iptables script runs
        log_info "Waiting briefly for tunnel interface..."
        sleep 2
    else
        log_error_and_exit "VPN (${vpn_type}) failed to start correctly. Cannot launch qBittorrent securely. Check previous logs."
    fi
}

display_vpn_disabled_warning() {
    log_warning "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    log_warning "THE CONTAINER IS RUNNING WITH VPN DISABLED"
    log_warning "PLEASE MAKE SURE VPN_ENABLED IS SET TO 'yes'"
    log_warning "IF THIS IS INTENTIONAL, YOU CAN IGNORE THIS"
    log_warning "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
}

start_qbittorrent() {
    local -r vpn_enabled="${1}"

    if [[ "${vpn_enabled}" =~ ${TRUE_REGEX} ]]; then
        log_info "Executing iptables script to configure firewall and start qBittorrent..."
        exec /bin/bash /etc/qbittorrent/iptables.sh
    else
        log_info "Executing standard qBittorrent start script (VPN disabled)..."
        exec /bin/bash /etc/qbittorrent/start.sh
    fi

    # If exec fails for some reason (e.g., script not found/executable), log error.
    log_error_and_exit "Failed to execute the target qBittorrent start script. Path: ${target_script}"
}