#!/bin/bash

readonly LOG_DATE_FORMAT_MANUAL='+%Y-%m-%d %H:%M:%S'
readonly LOG_DATE_FORMAT_TS='%Y-%m-%d %H:%M:%S'
readonly TRUE_REGEX='^(1|true|yes)$'

# Internal helper to add timestamp to a message string.
# Uses 'ts' command if available for precise timestamping of stdin,
# otherwise falls back to using 'date' for a basic timestamp prefix.
_log_timestamp() {
    local message="${1}"
    if command -v ts >/dev/null 2>&1; then
        printf "%s\n" "${message}" | ts "${LOG_DATE_FORMAT_TS}"
    else
        printf "[%s] %s\n" "$(date "${LOG_DATE_FORMAT_MANUAL}")" "${message}"
    fi
}

log_error_and_exit() {
    local message="${1}"
    local exit_code="${2:-1}"

    _log_timestamp "[ERROR] ${message}" >&2

    sleep 5

    exit "${exit_code}"
}

log_warning() {
    local message="${1}"
    
    _log_timestamp "[WARNING] ${message}" >&2
}

log_info() {
    local message="${1}"

    _log_timestamp "[INFO] ${message}"
}

log_debug() {
    local message="${1}"

    if [[ "${DEBUG,,}" =~ ${TRUE_REGEX} ]]; then
         _log_timestamp "[DEBUG] ${message}"
    fi
}

convert_to_unix() {
    local file="${1}"

    if [[ ! -f "${file}" ]]; then
        log_warning "Cannot convert non-existent file to Unix format: ${file}"
        return 1
    fi

    if command -v dos2unix >/dev/null 2>&1; then
        log_debug "Attempting dos2unix conversion for: ${file}"
        # redirect stdout/stderr of dos2unix to avoid polluting logs unless DEBUG is on
        if [[ "${DEBUG,,}" =~ ${TRUE_REGEX} ]]; then
             if dos2unix "${file}"; then
                log_debug "Successfully converted ${file} to Unix line endings."
                return 0
             else
                 log_warning "dos2unix command failed for file: ${file}. Check file permissions or content."
                return 1
             fi
        else
            if dos2unix "${file}" >/dev/null 2>&1; then
                return 0
            else
                log_warning "dos2unix command failed for file: ${file}. Check file permissions or content."
                return 1
            fi
        fi
    else
        log_warning "'dos2unix' command not found. Skipping line ending conversion for ${file}."
        return 0
    fi
}

validate_value() {
    local description="${1}"
    local value="${2}"
    local details="${3:-}"

    if [[ -z "${value}" ]]; then
        local error_message
        error_message=$(printf "'%s' is empty or not set." "${description}")
        if [[ -n "${details}" ]]; then
            error_message="${error_message} ${details}"
        fi
        log_error_and_exit "${error_message}"
    else
        log_debug "'${description}' validated successfully."
        : # bash requires a command here, ':' is a no-op
    fi
}