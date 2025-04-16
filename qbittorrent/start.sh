#!/bin/bash

# TODO: Re-use PIDFILE from qbittorrent.init
PIDFILE="/tmp/qbittorrent.pid"

VPN_QUALITY_CHECK_INTERVAL=${VPN_QUALITY_CHECK_INTERVAL:-3600} # check once per hour by default
last_quality_check_time=0

# Check if /config/qBittorrent exists, if not make the directory
if [[ ! -e /config/qBittorrent/config ]]; then
    mkdir -p /config/qBittorrent/config
fi
# Set the correct rights accordingly to the PUID and PGID on /config/qBittorrent
chown -R ${PUID}:${PGID} /config/qBittorrent

# Set the rights on the /downloads folder
find /downloads -not -user ${PUID} -execdir chown ${PUID}:${PGID} {} \+

# Check if qBittorrent.conf exists, if not, copy the template over
if [ ! -e /config/qBittorrent/config/qBittorrent.conf ]; then
    echo "[WARNING] qBittorrent.conf is missing, this is normal for the first launch! Copying template." | ts '%Y-%m-%d %H:%M:%.S'
    cp /etc/qbittorrent/qBittorrent.conf /config/qBittorrent/config/qBittorrent.conf
    chmod 755 /config/qBittorrent/config/qBittorrent.conf
    chown ${PUID}:${PGID} /config/qBittorrent/config/qBittorrent.conf
fi

export INSTALL_PYTHON3=$(echo "${INSTALL_PYTHON3,,}")
if [[ $INSTALL_PYTHON3 == "1" || $INSTALL_PYTHON3 == "true" || $INSTALL_PYTHON3 == "yes" ]]; then
    /bin/bash /etc/qbittorrent/install-python3.sh
fi

# The mess down here checks if SSL is enabled.
export ENABLE_SSL=$(echo "${ENABLE_SSL,,}")

if [[ ${ENABLE_SSL} == "1" || ${ENABLE_SSL} == "true" || ${ENABLE_SSL} == "yes" ]]; then
    echo "[INFO] ENABLE_SSL is set to '${ENABLE_SSL}'" | ts '%Y-%m-%d %H:%M:%.S'
    if [[ ${HOST_OS,,} == 'unraid' ]]; then
        echo "[SYSTEM] If you use Unraid, and get something like a 'ERR_EMPTY_RESPONSE' in your browser, add https:// to the front of the IP, and/or do this:" | ts '%Y-%m-%d %H:%M:%.S'
        echo "[SYSTEM] Edit this Docker, change the slider in the top right to 'advanced view' and change http to https at the WebUI setting." | ts '%Y-%m-%d %H:%M:%.S'
    fi
    if [ ! -e /config/qBittorrent/config/WebUICertificate.crt ]; then
        echo "[WARNING] WebUI Certificate is missing, generating a new Certificate and Key" | ts '%Y-%m-%d %H:%M:%.S'
        openssl req -new -x509 -nodes -out /config/qBittorrent/config/WebUICertificate.crt -keyout /config/qBittorrent/config/WebUIKey.key -subj "/C=NL/ST=localhost/L=localhost/O=/OU=/CN="
        chown -R ${PUID}:${PGID} /config/qBittorrent/config
    elif [ ! -e /config/qBittorrent/config/WebUIKey.key ]; then
        echo "[WARNING] WebUI Key is missing, generating a new Certificate and Key" | ts '%Y-%m-%d %H:%M:%.S'
        openssl req -new -x509 -nodes -out /config/qBittorrent/config/WebUICertificate.crt -keyout /config/qBittorrent/config/WebUIKey.key -subj "/C=NL/ST=localhost/L=localhost/O=/OU=/CN="
        chown -R ${PUID}:${PGID} /config/qBittorrent/config
    fi
    if grep -Fxq 'WebUI\HTTPS\CertificatePath=/config/qBittorrent/config/WebUICertificate.crt' "/config/qBittorrent/config/qBittorrent.conf"; then
        echo "[INFO] /config/qBittorrent/config/qBittorrent.conf already has the line WebUICertificate.crt loaded, nothing to do." | ts '%Y-%m-%d %H:%M:%.S'
    else
        echo "[WARNING] /config/qBittorrent/config/qBittorrent.conf doesn't have the WebUICertificate.crt loaded. Added it to the config." | ts '%Y-%m-%d %H:%M:%.S'
        echo 'WebUI\HTTPS\CertificatePath=/config/qBittorrent/config/WebUICertificate.crt' >>"/config/qBittorrent/config/qBittorrent.conf"
    fi
    if grep -Fxq 'WebUI\HTTPS\KeyPath=/config/qBittorrent/config/WebUIKey.key' "/config/qBittorrent/config/qBittorrent.conf"; then
        echo "[INFO] /config/qBittorrent/config/qBittorrent.conf already has the line WebUIKey.key loaded, nothing to do." | ts '%Y-%m-%d %H:%M:%.S'
    else
        echo "[WARNING] /config/qBittorrent/config/qBittorrent.conf doesn't have the WebUIKey.key loaded. Added it to the config." | ts '%Y-%m-%d %H:%M:%.S'
        echo 'WebUI\HTTPS\KeyPath=/config/qBittorrent/config/WebUIKey.key' >>"/config/qBittorrent/config/qBittorrent.conf"
    fi
    if grep -xq 'WebUI\\HTTPS\\Enabled=true\|WebUI\\HTTPS\\Enabled=false' "/config/qBittorrent/config/qBittorrent.conf"; then
        if grep -xq 'WebUI\\HTTPS\\Enabled=false' "/config/qBittorrent/config/qBittorrent.conf"; then
            echo "[WARNING] /config/qBittorrent/config/qBittorrent.conf does have the WebUI\HTTPS\Enabled set to false, changing it to true." | ts '%Y-%m-%d %H:%M:%.S'
            sed -i 's/WebUI\\HTTPS\\Enabled=false/WebUI\\HTTPS\\Enabled=true/g' "/config/qBittorrent/config/qBittorrent.conf"
        else
            echo "[INFO] /config/qBittorrent/config/qBittorrent.conf does have the WebUI\HTTPS\Enabled already set to true." | ts '%Y-%m-%d %H:%M:%.S'
        fi
    else
        echo "[WARNING] /config/qBittorrent/config/qBittorrent.conf doesn't have the WebUI\HTTPS\Enabled loaded. Added it to the config." | ts '%Y-%m-%d %H:%M:%.S'
        echo 'WebUI\HTTPS\Enabled=true' >>"/config/qBittorrent/config/qBittorrent.conf"
    fi
else
    echo "[WARNING] ENABLE_SSL is set to '${ENABLE_SSL}', SSL is not enabled. This could cause issues with logging if other apps use the same Cookie name (SID)." | ts '%Y-%m-%d %H:%M:%.S'
    echo "[WARNING] Removing the SSL configuration from the config file..." | ts '%Y-%m-%d %H:%M:%.S'
    sed -i '/^WebUI\\HTTPS*/d' "/config/qBittorrent/config/qBittorrent.conf"
fi

QBIT_CONFIG_FILE="/config/qBittorrent/config/qBittorrent.conf"
PREFERENCES_HEADER="[Preferences]"

ensure_preferences_header() {
    if ! grep -q "^\s*${PREFERENCES_HEADER}\s*$" "${QBIT_CONFIG_FILE}"; then
        echo "[INFO] ${PREFERENCES_HEADER} header not found in ${QBIT_CONFIG_FILE}, adding it." | ts '%Y-%m-%d %H:%M:%.S'
        echo -e "\n${PREFERENCES_HEADER}" >>"${QBIT_CONFIG_FILE}"
    fi
}

if [ -v QBIT_AUTH_SUBNET_WHITELIST_ENABLED ]; then
    QBIT_AUTH_SUBNET_WHITELIST_ENABLED_NORM=$(echo "${QBIT_AUTH_SUBNET_WHITELIST_ENABLED,,}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

    desired_enabled_value="false"
    if [[ "${QBIT_AUTH_SUBNET_WHITELIST_ENABLED_NORM}" =~ ^(1|true|yes)$ ]]; then
        desired_enabled_value="true"
    fi

    echo "[INFO] Setting WebUI\\AuthSubnetWhitelistEnabled=${desired_enabled_value} in ${QBIT_CONFIG_FILE} based on ENV var." | ts '%Y-%m-%d %H:%M:%.S'
    ensure_preferences_header
    
    sed -i -e '\#^WebUI\\AuthSubnetWhitelistEnabled=.*#d' "${QBIT_CONFIG_FILE}"
    echo "WebUI\AuthSubnetWhitelistEnabled=${desired_enabled_value}" >>"${QBIT_CONFIG_FILE}"
else
    echo "[INFO] QBIT_AUTH_SUBNET_WHITELIST_ENABLED not set, using value from ${QBIT_CONFIG_FILE} (or template default)." | ts '%Y-%m-%d %H:%M:%.S'
fi

if [ -v QBIT_AUTH_SUBNET_WHITELIST ]; then
    echo "[INFO] Setting WebUI\\AuthSubnetWhitelist='${QBIT_AUTH_SUBNET_WHITELIST}' in ${QBIT_CONFIG_FILE} based on ENV var." | ts '%Y-%m-%d %H:%M:%.S'
    ensure_preferences_header
    
    sed -i -e '\#^WebUI\\AuthSubnetWhitelist=.*#d' "${QBIT_CONFIG_FILE}"
    echo "WebUI\AuthSubnetWhitelist=${QBIT_AUTH_SUBNET_WHITELIST}" >>"${QBIT_CONFIG_FILE}"
else
    echo "[INFO] QBIT_AUTH_SUBNET_WHITELIST not set, using value from ${QBIT_CONFIG_FILE} (or template default)." | ts '%Y-%m-%d %H:%M:%.S'
fi

if getent group ${PGID} >/dev/null 2>&1; then
    GROUP_NAME=$(getent group ${PGID} | cut -d: -f1)
    echo "[INFO] Group with PGID ${PGID} exists with name '${GROUP_NAME}'" | ts '%Y-%m-%d %H:%M:%.S'
else
    GROUP_NAME="qbittorrent"
    echo "[INFO] Creating group '${GROUP_NAME}' with PGID ${PGID}" | ts '%Y-%m-%d %H:%M:%.S'
    groupadd -g ${PGID} ${GROUP_NAME} || {
        echo "[WARNING] Failed to create group with PGID ${PGID}, using existing group" | ts '%Y-%m-%d %H:%M:%.S'
        GROUP_NAME=$(grep -m1 ":x:${PGID}:" /etc/group | cut -d: -f1 || echo "root")
    }
fi

USER_EXISTS=0
if id ${PUID} >/dev/null 2>&1 || getent passwd ${PUID} >/dev/null 2>&1; then
    USER_EXISTS=1
    USER_NAME=$(getent passwd ${PUID} | cut -d: -f1)
    echo "[INFO] User with PUID ${PUID} exists with name '${USER_NAME}'" | ts '%Y-%m-%d %H:%M:%.S'
else
    USER_NAME="qbittorrent"
    echo "[INFO] Creating user '${USER_NAME}' with PUID ${PUID} in group '${GROUP_NAME}'" | ts '%Y-%m-%d %H:%M:%.S'
    adduser -D -u ${PUID} -G ${GROUP_NAME} ${USER_NAME} || {
        # if creation fails, try to understand why
        if getent passwd ${PUID} >/dev/null 2>&1; then
            USER_NAME=$(getent passwd ${PUID} | cut -d: -f1)
            echo "[WARNING] User with PUID ${PUID} already exists as '${USER_NAME}', using existing user" | ts '%Y-%m-%d %H:%M:%.S'
            USER_EXISTS=1
        else
            # creation genuinely failed, attempt fallback
            echo "[WARNING] Failed to create user with standard method, trying alternative approach" | ts '%Y-%m-%d %H:%M:%.S'
            # try alternate method with a random unused UID and then modify it
            TEMP_UID=$(shuf -i 2000-3000 -n 1)
            adduser -D -u ${TEMP_UID} ${USER_NAME} && usermod -u ${PUID} ${USER_NAME} || {
                echo "[ERROR] All user creation methods failed. Using existing user 'nobody'" | ts '%Y-%m-%d %H:%M:%.S'
                USER_NAME="nobody"
            }
        fi
    }
fi

if [ ${USER_EXISTS} -eq 0 ] && [ "${USER_NAME}" != "nobody" ]; then
    usermod -g ${GROUP_NAME} ${USER_NAME} || echo "[WARNING] Failed to set correct group for user" | ts '%Y-%m-%d %H:%M:%.S'
fi

export QBIT_USER=${USER_NAME}
export QBIT_GROUP=${GROUP_NAME}

echo "[INFO] qBittorrent will run as user: ${QBIT_USER} (${PUID}) and group: ${QBIT_GROUP} (${PGID})" | ts '%Y-%m-%d %H:%M:%.S'

# Set the umask
if [[ ! -z "${UMASK}" ]]; then
    echo "[INFO] UMASK defined as '${UMASK}'" | ts '%Y-%m-%d %H:%M:%.S'
    export UMASK=$(echo "${UMASK}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
else
    echo "[WARNING] UMASK not defined (via -e UMASK), defaulting to '002'" | ts '%Y-%m-%d %H:%M:%.S'
    export UMASK="002"
fi

# Start qBittorrent
echo "[INFO] Starting qBittorrent daemon..." | ts '%Y-%m-%d %H:%M:%.S'
/bin/bash /etc/qbittorrent/qbittorrent.init start
init_status=$?
chmod -R 755 /config/qBittorrent

if [ $init_status -ne 0 ]; then
    echo "[ERROR] Failed to start qBittorrent daemon (exit code: $init_status)" | ts '%Y-%m-%d %H:%M:%.S'
    exit 1
fi

# Wait up to 10 seconds for PID file
max_attempts=10
attempt=0
while [ ! -f "$PIDFILE" ] && [ $attempt -lt $max_attempts ]; do
    echo "[INFO] Waiting for qBittorrent PID file '$PIDFILE' (attempt $((attempt + 1))/$max_attempts)..." | ts '%Y-%m-%d %H:%M:%.S'
    sleep 1
    attempt=$((attempt + 1))
done

# Check if PID file exists and contains a valid PID
if [ -f "$PIDFILE" ]; then
    qbittorrentpid=$(cat "$PIDFILE")
    if kill -0 "$qbittorrentpid" 2>/dev/null; then
        echo "[INFO] qBittorrent started successfully with PID: $qbittorrentpid" | ts '%Y-%m-%d %H:%M:%.S'
        echo "[DEBUG] Starting health check loop for qBittorrent pid ${qbittorrentpid}" | ts '%Y-%m-%d %H:%M:%.S'
    else
        echo "[ERROR] qBittorrent PID file exists but process is not running" | ts '%Y-%m-%d %H:%M:%.S'
        exit 1
    fi
else
    echo "[ERROR] Failed to find qBittorrent PID file after $max_attempts attempts" | ts '%Y-%m-%d %H:%M:%.S'
    exit 1
fi

check_vpn_health() {
    local retry_count=0
    local max_retries=3
    local backoff_time=5

    while [ $retry_count -lt $max_retries ]; do
        if ! ip link show ${VPN_DEVICE_TYPE} &>/dev/null; then
            echo "[WARNING] VPN interface ${VPN_DEVICE_TYPE} is down (attempt $((retry_count + 1))/$max_retries)." | ts '%Y-%m-%d %H:%M:%.S'
            retry_count=$((retry_count + 1))
            sleep $backoff_time
            backoff_time=$((backoff_time * 2))
            continue
        fi

        local external_ip
        external_ip=$(curl --interface ${VPN_DEVICE_TYPE} --silent --max-time 5 "https://api.ipify.org" ||
            curl --interface ${VPN_DEVICE_TYPE} --silent --max-time 5 "https://ifconfig.me" ||
            curl --interface ${VPN_DEVICE_TYPE} --silent --max-time 5 "https://icanhazip.com" ||
            echo "")

        if [[ -z "${external_ip}" ]]; then
            echo "[WARNING] Failed to get external IP through VPN interface (attempt $((retry_count + 1))/$max_retries)." | ts '%Y-%m-%d %H:%M:%.S'
            retry_count=$((retry_count + 1))
            sleep $backoff_time
            backoff_time=$((backoff_time * 2))
            continue
        fi

        if ! nslookup -timeout=5 example.com &>/dev/null; then
            echo "[WARNING] DNS resolution failed (attempt $((retry_count + 1))/$max_retries)." | ts '%Y-%m-%d %H:%M:%.S'
            retry_count=$((retry_count + 1))
            sleep $backoff_time
            backoff_time=$((backoff_time * 2))
            continue
        fi

        if [[ -z "${VPN_IP}" ]]; then
            export VPN_IP="${external_ip}"
            echo "[INFO] VPN connected with IP: ${VPN_IP}" | ts '%Y-%m-%d %H:%M:%.S'
        elif [[ "${external_ip}" != "${VPN_IP}" ]]; then
            echo "[INFO] VPN IP changed from ${VPN_IP} to ${external_ip}" | ts '%Y-%m-%d %H:%M:%.S'
            export VPN_IP="${external_ip}"
        fi

        return 0
    done

    echo "[ERROR] VPN health check failed after $max_retries attempts." | ts '%Y-%m-%d %H:%M:%.S'
    return 1
}

measure_vpn_quality() {
    echo "[INFO] Measuring VPN connection quality..." | ts '%Y-%m-%d %H:%M:%.S'

    local gateway=$(ip route | grep "${VPN_DEVICE_TYPE}" | grep "via" | head -1 | awk '{print $3}')

    if [[ -n "${gateway}" ]]; then
        echo "[INFO] VPN gateway identified as: ${gateway}" | ts '%Y-%m-%d %H:%M:%.S'

        ping -c 2 -W 1 -I "${VPN_DEVICE_TYPE}" "${gateway}" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "[INFO] VPN gateway is responsive to ping" | ts '%Y-%m-%d %H:%M:%.S'
        else
            echo "[INFO] VPN gateway does not respond to ping (common security practice)" | ts '%Y-%m-%d %H:%M:%.S'
        fi
    else
        echo "[INFO] Could not identify VPN gateway from routing table" | ts '%Y-%m-%d %H:%M:%.S'
    fi

    echo "[INFO] Testing internet connectivity through VPN..." | ts '%Y-%m-%d %H:%M:%.S'

    local test_targets=("1.1.1.1" "8.8.8.8" "9.9.9.9")
    local successful_tests=0
    local total_rtt=0
    local test_count=0

    for target in "${test_targets[@]}"; do
        echo "[INFO] Testing connectivity to ${target}..." | ts '%Y-%m-%d %H:%M:%.S'

        local ping_output=$(ping -c 3 -W 2 -I "${VPN_DEVICE_TYPE}" "${target}" 2>/dev/null)
        local ping_status=$?

        if [ ${ping_status} -eq 0 ]; then
            successful_tests=$((successful_tests + 1))

            local avg_rtt=$(grep "round-trip min/avg/max" <<<"${ping_output}" | awk -F= '{print $2}' | awk -F/ '{print $2}' | awk '{print $1}')

            if [[ -n "${avg_rtt}" ]]; then
                echo "[INFO] Latency to ${target}: ${avg_rtt} ms" | ts '%Y-%m-%d %H:%M:%.S'
                test_count=$((test_count + 1))
                total_rtt=$(echo "${total_rtt} + ${avg_rtt}" | bc 2>/dev/null || echo "${total_rtt}")
            else
                # fall back to calculating from individual ping times
                avg_rtt=$(grep -o "time=[0-9.]\+ ms" <<<"${ping_output}" | grep -o "[0-9.]\+" | awk '{ sum += $1; n++ } END { if (n > 0) print sum / n; }')

                if [[ -n "${avg_rtt}" ]]; then
                    echo "[INFO] Latency to ${target}: ${avg_rtt} ms" | ts '%Y-%m-%d %H:%M:%.S'
                    test_count=$((test_count + 1))
                    total_rtt=$(echo "${total_rtt} + ${avg_rtt}" | bc 2>/dev/null || echo "${total_rtt}")
                else
                    echo "[INFO] Could not determine latency to ${target}" | ts '%Y-%m-%d %H:%M:%.S'
                fi
            fi
        else
            echo "[INFO] Ping test to ${target} failed, trying TCP test..." | ts '%Y-%m-%d %H:%M:%.S'

            # try TCP test to common ports (use timeout to prevent hanging)
            if timeout 3 curl --interface "${VPN_DEVICE_TYPE}" --silent --head --fail --max-time 2 "https://${target}" >/dev/null 2>&1; then
                echo "[INFO] TCP connectivity to ${target} (HTTPS) successful" | ts '%Y-%m-%d %H:%M:%.S'
                successful_tests=$((successful_tests + 1))
            elif timeout 3 curl --interface "${VPN_DEVICE_TYPE}" --silent --head --fail --max-time 2 "http://${target}" >/dev/null 2>&1; then
                echo "[INFO] TCP connectivity to ${target} (HTTP) successful" | ts '%Y-%m-%d %H:%M:%.S'
                successful_tests=$((successful_tests + 1))
            else
                echo "[WARNING] All connectivity tests to ${target} failed" | ts '%Y-%m-%d %H:%M:%.S'
            fi
        fi
    done

    if [ ${successful_tests} -eq ${#test_targets[@]} ]; then
        echo "[INFO] VPN connectivity: Excellent (${successful_tests}/${#test_targets[@]} targets reachable)" | ts '%Y-%m-%d %H:%M:%.S'
    elif [ ${successful_tests} -gt 0 ]; then
        echo "[INFO] VPN connectivity: Limited (${successful_tests}/${#test_targets[@]} targets reachable)" | ts '%Y-%m-%d %H:%M:%.S'
    else
        echo "[ERROR] VPN connectivity: Failed (0/${#test_targets[@]} targets reachable)" | ts '%Y-%m-%d %H:%M:%.S'
    fi

    if [ ${test_count} -gt 0 ]; then
        local avg_latency=$(echo "scale=1; ${total_rtt} / ${test_count}" | bc 2>/dev/null)

        if [[ -z "${avg_latency}" || "${avg_latency}" == "0" ]]; then
            if [ ${total_rtt} -gt 0 ]; then
                avg_latency=$((total_rtt / test_count))
            else
                avg_latency=0
            fi
        fi

        echo "[INFO] Average latency: ${avg_latency} ms" | ts '%Y-%m-%d %H:%M:%.S'

        if (($(echo "${avg_latency} > 100" | bc 2>/dev/null || echo "0"))); then
            echo "[WARNING] High average latency (${avg_latency} ms) may impact performance" | ts '%Y-%m-%d %H:%M:%.S'
        elif (($(echo "${avg_latency} > 50" | bc 2>/dev/null || echo "0"))); then
            echo "[INFO] Average latency (${avg_latency} ms) is acceptable" | ts '%Y-%m-%d %H:%M:%.S'
        else
            echo "[INFO] Average latency (${avg_latency} ms) is excellent" | ts '%Y-%m-%d %H:%M:%.S'
        fi
    else
        echo "[INFO] Could not calculate average latency" | ts '%Y-%m-%d %H:%M:%.S'
    fi

    echo "[INFO] Testing MTU..." | ts '%Y-%m-%d %H:%M:%.S'

    local current_mtu=$(ip link show "${VPN_DEVICE_TYPE}" 2>/dev/null | grep -o 'mtu [0-9]*' | awk '{print $2}')

    if [[ -n "${current_mtu}" ]]; then
        echo "[INFO] Current ${VPN_DEVICE_TYPE} MTU: ${current_mtu}" | ts '%Y-%m-%d %H:%M:%.S'

        # test connectivity with current MTU to a reliable target
        local test_target="1.1.1.1"
        local test_size=$((current_mtu - 28)) # account for IP and ICMP headers...

        if ping -c 2 -s "${test_size}" -I "${VPN_DEVICE_TYPE}" "${test_target}" >/dev/null 2>&1; then
            echo "[INFO] Current MTU appears to be working correctly" | ts '%Y-%m-%d %H:%M:%.S'
        else
            echo "[WARNING] Current MTU may be too high, testing with reduced size..." | ts '%Y-%m-%d %H:%M:%.S'

            # try with a more conservative MTU
            local reduced_size=$((test_size - 40))
            if ping -c 2 -s "${reduced_size}" -I "${VPN_DEVICE_TYPE}" "${test_target}" >/dev/null 2>&1; then
                echo "[INFO] Reduced MTU test successful. Consider setting MTU to $((reduced_size + 28))" | ts '%Y-%m-%d %H:%M:%.S'
            else
                echo "[WARNING] MTU tests failed. VPN may have connectivity issues" | ts '%Y-%m-%d %H:%M:%.S'
            fi
        fi
    else
        echo "[WARNING] Could not determine current MTU" | ts '%Y-%m-%d %H:%M:%.S'
    fi

    # check VPN throughput with a small download test (if enabled)
    if [[ "${VPN_QUALITY_CHECK_SPEED:-no}" =~ ^(1|true|yes)$ ]]; then
        echo "[INFO] Testing download speed (small test)..." | ts '%Y-%m-%d %H:%M:%.S'

        local speed_result=$(curl --interface "${VPN_DEVICE_TYPE}" -s -w "%{speed_download}" -o /dev/null https://speed.cloudflare.com/__down?bytes=1000000 2>/dev/null)

        if [[ -n "${speed_result}" && "${speed_result}" != "0" ]]; then
            # convert to Mbps (curl reports in bytes/sec)
            local mbps=$(echo "scale=2; ${speed_result} * 8 / 1000000" | bc -l 2>/dev/null || echo "N/A")
            echo "[INFO] Download speed: ${mbps} Mbps" | ts '%Y-%m-%d %H:%M:%.S'

            if (($(echo "${mbps} < 5" | bc -l 2>/dev/null || echo "0"))); then
                echo "[WARNING] Low download speed may impact performance" | ts '%Y-%m-%d %H:%M:%.S'
            fi
        else
            echo "[WARNING] Speed test failed" | ts '%Y-%m-%d %H:%M:%.S'
        fi
    fi

    # Check for IP leaks
    if [[ -n "${VPN_IP}" ]]; then
        echo "[INFO] VPN IP address: ${VPN_IP}" | ts '%Y-%m-%d %H:%M:%.S'

        # Get current external IP through VPN
        local current_ip=""
        for ip_service in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com"; do
            current_ip=$(curl --interface "${VPN_DEVICE_TYPE}" --silent --max-time 5 "${ip_service}" 2>/dev/null || echo "")
            if [[ -n "${current_ip}" ]]; then
                break
            fi
        done

        if [[ -n "${current_ip}" ]]; then
            if [[ "${current_ip}" != "${VPN_IP}" ]]; then
                echo "[WARNING] IP address has changed from ${VPN_IP} to ${current_ip}" | ts '%Y-%m-%d %H:%M:%.S'
                # Update the stored IP
                export VPN_IP="${current_ip}"
            else
                echo "[INFO] IP address unchanged: ${VPN_IP}" | ts '%Y-%m-%d %H:%M:%.S'
            fi
        else
            echo "[WARNING] Could not verify current IP address" | ts '%Y-%m-%d %H:%M:%.S'
        fi
    fi

    echo "[INFO] VPN quality check complete" | ts '%Y-%m-%d %H:%M:%.S'
}

perform_detailed_health_check() {
    if [[ -n "${VPN_IP}" ]]; then
        echo "[INFO] VPN connected - IP: ${VPN_IP}" | ts '%Y-%m-%d %H:%M:%.S'
    fi

    local hosts=("one.one.one.one" "google.com")
    local total_hosts=${#hosts[@]}
    local reachable_hosts=0
    local total_latency=0

    echo "[INFO] Network statistics:" | ts '%Y-%m-%d %H:%M:%.S'

    for host in "${hosts[@]}"; do
        if ping -c 3 -W 2 "${host}" &>/dev/null; then
            ping_output=$(ping -c 3 -W 2 "${host}" 2>/dev/null)

            # extract the round-trip line which contains min/avg/max
            # format looks like: "round-trip min/avg/max = 14.123/15.369/16.185 ms"
            rtt_line=$(echo "$ping_output" | grep -i "round-trip")

            if [[ -n "$rtt_line" ]]; then
                # extract the avg value - should be the middle number in the min/avg/max triplet
                latency=$(echo "$rtt_line" | cut -d'=' -f2 | tr '/' ' ' | awk '{print $2}')

                if [[ -n "$latency" ]]; then
                    reachable_hosts=$((reachable_hosts + 1))
                    latency_int=$(printf "%.0f" "${latency%.*}${latency#*.}")
                    total_latency=$((total_latency + latency_int))
                    echo "[INFO] ├─ ${host}: ${latency} ms" | ts '%Y-%m-%d %H:%M:%.S'
                else
                    echo "[INFO] ├─ ${host}: connected (latency unknown)" | ts '%Y-%m-%d %H:%M:%.S'
                fi
            else
                time_values=$(echo "$ping_output" | grep -o "time=[0-9.]\+" | cut -d= -f2)
                if [[ -n "$time_values" ]]; then
                    # calc average from individual times
                    count=0
                    sum=0
                    while read -r time; do
                        count=$((count + 1))
                        time_int=$(printf "%.0f" "$(echo "${time} * 100" | sed 's/\.//g')")
                        sum=$((sum + time_int))
                    done <<<"$time_values"

                    if [[ $count -gt 0 ]]; then
                        avg=$((sum / count))
                        latency="$((avg / 100)).$((avg % 100))"
                        reachable_hosts=$((reachable_hosts + 1))
                        total_latency=$((total_latency + avg))
                        echo "[INFO] ├─ ${host}: ${latency} ms" | ts '%Y-%m-%d %H:%M:%.S'
                    else
                        echo "[INFO] ├─ ${host}: connected (latency unknown)" | ts '%Y-%m-%d %H:%M:%.S'
                    fi
                else
                    echo "[INFO] ├─ ${host}: connected (latency unknown)" | ts '%Y-%m-%d %H:%M:%.S'
                fi
            fi
        else
            echo "[INFO] ├─ ${host}: unreachable" | ts '%Y-%m-%d %H:%M:%.S'
        fi
    done

    if [ $reachable_hosts -gt 0 ] && [ $total_latency -gt 0 ]; then
        local avg_latency_int=$((total_latency / reachable_hosts))
        local avg_latency_main=$((avg_latency_int / 100))
        local avg_latency_frac=$((avg_latency_int % 100))
        if [ $avg_latency_frac -lt 10 ]; then
            echo "[INFO] └─ Average latency: ${avg_latency_main}.0${avg_latency_frac} ms" | ts '%Y-%m-%d %H:%M:%.S'
        else
            echo "[INFO] └─ Average latency: ${avg_latency_main}.${avg_latency_frac} ms" | ts '%Y-%m-%d %H:%M:%.S'
        fi
    else
        echo "[INFO] └─ Average latency: unavailable" | ts '%Y-%m-%d %H:%M:%.S'
    fi

    if [[ -n "${VPN_DEVICE_TYPE}" && -e "/sys/class/net/${VPN_DEVICE_TYPE}" ]]; then
        rx_bytes=$(cat "/sys/class/net/${VPN_DEVICE_TYPE}/statistics/rx_bytes" 2>/dev/null || echo "0")
        tx_bytes=$(cat "/sys/class/net/${VPN_DEVICE_TYPE}/statistics/tx_bytes" 2>/dev/null || echo "0")

        format_bytes() {
            local bytes=$1
            local divisor=1
            local unit="B"

            if [ $bytes -ge 1073741824 ]; then # 1 GiB
                divisor=1073741824
                unit="GB"
            elif [ $bytes -ge 1048576 ]; then # 1 MiB
                divisor=1048576
                unit="MB"
            elif [ $bytes -ge 1024 ]; then # 1 KiB
                divisor=1024
                unit="KB"
            fi

            if [ $divisor -eq 1 ]; then
                echo "${bytes}${unit}"
            else
                local whole=$((bytes / divisor))
                local remainder=$((bytes % divisor))
                local decimal=$((remainder * 100 / divisor))
                if [ $decimal -lt 10 ]; then
                    echo "${whole}.0${decimal}${unit}"
                else
                    echo "${whole}.${decimal}${unit}"
                fi
            fi
        }

        local rx_human=$(format_bytes "$rx_bytes")
        local tx_human=$(format_bytes "$tx_bytes")

        echo "[INFO] VPN interface (${VPN_DEVICE_TYPE}) statistics:" | ts '%Y-%m-%d %H:%M:%.S'
        echo "[INFO] ├─ Total received: ${rx_human}" | ts '%Y-%m-%d %H:%M:%.S'
        echo "[INFO] └─ Total sent: ${tx_human}" | ts '%Y-%m-%d %H:%M:%.S'
    fi

    # check qBittorrent status
    if [ -f "${PIDFILE}" ]; then
        qbt_pid=$(cat "${PIDFILE}")
        if kill -0 "${qbt_pid}" 2>/dev/null; then
            echo "[INFO] qBittorrent is running (PID: ${qbt_pid})" | ts '%Y-%m-%d %H:%M:%.S'

            # add system load info
            if [ -f /proc/loadavg ]; then
                load=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
                echo "[INFO] System load (1m, 5m, 15m): ${load}" | ts '%Y-%m-%d %H:%M:%.S'
            fi
        else
            echo "[WARNING] qBittorrent process appears dead (PID: ${qbt_pid})" | ts '%Y-%m-%d %H:%M:%.S'
        fi
    else
        echo "[WARNING] qBittorrent is not running (no PID file)" | ts '%Y-%m-%d %H:%M:%.S'
    fi
}

# If the process exists, make sure that the log file has the proper rights and start the health check
if [ -e /proc/$qbittorrentpid ]; then
    echo "[INFO] qBittorrent PID: $qbittorrentpid" | ts '%Y-%m-%d %H:%M:%.S'

    # trap the TERM signal for propagation and graceful shutdowns
    handle_term() {
        echo "[INFO] Received SIGTERM, stopping..." | ts '%Y-%m-%d %H:%M:%.S'
        /bin/bash /etc/qbittorrent/qbittorrent.init stop
        exit $?
    }
    trap handle_term SIGTERM
    if [[ -e /config/qBittorrent/data/logs/qbittorrent.log ]]; then
        chmod 775 /config/qBittorrent/data/logs/qbittorrent.log
    fi

    # Set some variables that are used
    HOST=${HEALTH_CHECK_HOST}
    DEFAULT_HOST="one.one.one.one"
    INTERVAL=${HEALTH_CHECK_INTERVAL}
    DEFAULT_INTERVAL=300
    DEFAULT_HEALTH_CHECK_AMOUNT=1

    # If host is zero (not set) default it to the DEFAULT_HOST variable
    if [[ -z "${HOST}" ]]; then
        echo "[INFO] HEALTH_CHECK_HOST is not set. For now using default host ${DEFAULT_HOST}" | ts '%Y-%m-%d %H:%M:%.S'
        HOST=${DEFAULT_HOST}
    fi

    # If HEALTH_CHECK_INTERVAL is zero (not set) default it to DEFAULT_INTERVAL
    if [[ -z "${HEALTH_CHECK_INTERVAL}" ]]; then
        echo "[INFO] HEALTH_CHECK_INTERVAL is not set. For now using default interval of ${DEFAULT_INTERVAL}" | ts '%Y-%m-%d %H:%M:%.S'
        INTERVAL=${DEFAULT_INTERVAL}
    fi

    # If HEALTH_CHECK_SILENT is zero (not set) default it to supression
    if [[ -z "${HEALTH_CHECK_SILENT}" ]]; then
        echo "[INFO] HEALTH_CHECK_SILENT is not set. Because this variable is not set, it will be supressed by default" | ts '%Y-%m-%d %H:%M:%.S'
        HEALTH_CHECK_SILENT=1
    fi

    if [ ! -z ${RESTART_CONTAINER} ]; then
        echo "[INFO] RESTART_CONTAINER defined as '${RESTART_CONTAINER}'" | ts '%Y-%m-%d %H:%M:%.S'
    else
        echo "[WARNING] RESTART_CONTAINER not defined,(via -e RESTART_CONTAINER), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
        export RESTART_CONTAINER="yes"
    fi

    # If HEALTH_CHECK_AMOUNT is zero (not set) default it to DEFAULT_HEALTH_CHECK_AMOUNT
    if [[ -z ${HEALTH_CHECK_AMOUNT} ]]; then
        echo "[INFO] HEALTH_CHECK_AMOUNT is not set. For now using default interval of ${DEFAULT_HEALTH_CHECK_AMOUNT}" | ts '%Y-%m-%d %H:%M:%.S'
        HEALTH_CHECK_AMOUNT=${DEFAULT_HEALTH_CHECK_AMOUNT}
    fi
    echo "[INFO] HEALTH_CHECK_AMOUNT is set to ${HEALTH_CHECK_AMOUNT}" | ts '%Y-%m-%d %H:%M:%.S'

    while true; do
        if ! check_vpn_health; then
            echo "[ERROR] VPN health check failed." | ts '%Y-%m-%d %H:%M:%.S'
            sleep 1
            if [[ ${RESTART_CONTAINER,,} == "1" || ${RESTART_CONTAINER,,} == "true" || ${RESTART_CONTAINER,,} == "yes" ]]; then
                echo "[INFO] Restarting container." | ts '%Y-%m-%d %H:%M:%.S'
                exit 1
            fi
        fi

        if [[ ${HEALTH_CHECK_SILENT,,} == "0" || ${HEALTH_CHECK_SILENT,,} == "false" || ${HEALTH_CHECK_SILENT,,} == "no" ]]; then
            perform_detailed_health_check
        fi

        if [[ ${VPN_QUALITY_CHECK_DISABLE} =~ ^(1|true|yes)$ ]]; then
            echo "[INFO] VPN quality check is disabled." | ts '%Y-%m-%d %H:%M:%.S'
        else
            current_time=$(date +%s)
            if [ $((current_time - last_quality_check_time)) -ge ${VPN_QUALITY_CHECK_INTERVAL} ]; then
                if [[ "${VPN_ENABLED}" =~ ^(1|true|yes)$ ]]; then
                    measure_vpn_quality

                    last_quality_check_time=${current_time}
                fi
            fi
        fi

        sleep ${INTERVAL} &
        # combine sleep background with wait so that the TERM trap above works
        wait $!
    done
else
    echo "[ERROR] qBittorrent failed to start!" | ts '%Y-%m-%d %H:%M:%.S'
fi
