#!/bin/bash

# Logging date format constant
readonly LOG_DATE_FORMAT='%Y-%m-%d %H:%M:%S'
# Regex indicating true-ish value
readonly TRUE_REGEX='^(1|true|yes)$'

# Function to log and exit on error. Argument should be the error message.
log_error_and_exit() {
    local -r message="$1"
    echo "[ERROR] ${message}" | ts "${LOG_DATE_FORMAT}"
    sleep 10
    exit 1
}

# Function to log a warning. Argument should be the warning message.
log_warning() {
    local -r message="$1"
    echo "[WARNING] ${message}" | ts "${LOG_DATE_FORMAT}"
}

# Function to log an information message. Argument should be the message.
log_info() {
    local -r message="$1"
    echo "[INFO] ${message}" | ts "${LOG_DATE_FORMAT}"
}

# Function to convert a file to Unix format
convert_to_unix() {
    local file="${1}"
    dos2unix "${file}" 1>/dev/null
}

validate_key_value() {
    local key="${1}"
    local value="${2}"
    local config_file="${3}"

    if [[ -n "${value}" ]]; then
        log_info "${key} defined as '${value}'"
    elif [[ -n "${config_file}" ]]; then
        log_error_and_exit "${key} not found in ${config_file}, exiting..."
    else
        log_error_and_exit "${key} not defined, exiting..."
    fi
}
