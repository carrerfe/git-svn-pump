#!/usr/bin/env bash

ACTIVITY_STACK=()
INDENT='-'
PADDING='  '

function log_message() {
    echo "$(date --rfc-3339=seconds) $@"
}

function begin_activity() {
    local ACTIVITY=$1
    ACTIVITY_STACK=( ${ACTIVITY} "${ACTIVITY_STACK[@]}" )

    if [ ${#ACTIVITY_STACK[@]} -eq 1 ]; then
        log_message "${ACTIVITY}...";
    else
        PADDING="${PADDING}${INDENT}"
        log_message "${PADDING} ${ACTIVITY}"
    fi
}

function done_activity() {
    local ACTIVITY=${ACTIVITY_STACK[0]}
    ACTIVITY_STACK=("${ACTIVITY_STACK[@]:1}")

    if [ ${#ACTIVITY_STACK[@]} -eq 1 ]; then
        log_message "${ACTIVITY}... [DONE]"
    else
        PADDING=${PADDING:0:$[ ${#PADDING} - ${#INDENT} ] }
    fi
}

function failed_activity() {
    local ACTIVITY=${ACTIVITY_STACK[0]}
    if [ ${#ACTIVITY_STACK[@]} -eq 1 ]; then
        log_message "${ACTIVITY}... [FAILED!]"
    else
        log_message $(printf '**%.0s' {2..${#ACTIVITY_STACK[@]}} ) "${ACTIVITY}" failed!
    fi
    return 1
}