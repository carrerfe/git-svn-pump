#!/usr/bin/env bash

. src/common.sh

ORIGINAL_DIR=${PWD}

BASE_DIR=${PWD}
SRC_DIR=${BASE_DIR}/src
TARGET_DIR=${BASE_DIR}/target

function print_config() {
    log_message "Build root path: ${BASE_DIR}"
    log_message "       SRC path: ${SRC_DIR}"
    log_message "    TARGET path: ${TARGET_DIR}"
    log_message '----------------------------------------------------------------------------'
}

function clean() {
    begin_activity 'Cleaning target dir'

    cd ${BASE_DIR} \
        && rm -rf ${TARGET_DIR}

    if [ ! $? -eq 0 ]; then
        failed_activity
        return 1
    fi

    done_activity
}

function create_target_dirs() {
    begin_activity "Creating target dirs"

    cd ${BASE_DIR} \
        && mkdir -p ${TARGET_DIR}/dist \
        && cd ${TARGET_DIR}/dist \
        && git init

    if [ ! $? -eq 0 ]; then
        failed_activity
        return 1
    fi

    done_activity
}

function copy_resources() {
    begin_activity "Copying resources"

    cp "${SRC_DIR}/basic_gitignore" "${TARGET_DIR}/dist/" \
        && cp "${SRC_DIR}/basic_svnignore" "${TARGET_DIR}/dist/" \
        && cp "${SRC_DIR}/pump.config" "${TARGET_DIR}/dist/pump.config.example" \
        && cp "${BASE_DIR}/LICENSE" "${TARGET_DIR}/dist/"

    if [ ! $? -eq 0 ]; then
        failed_activity
        return 1
    fi

    done_activity
}

function concat_scripts() {
    local OUTFILE=$1
    shift
    local INPUTFILES=$@
    begin_activity "Making ${OUTFILE}"

    local SHEBANG='#!/usr/bin/env bash'

    # appending SHEBANG line and COPYRIGHT content (as comment)
    echo ${SHEBANG} > "${OUTFILE}" \
    && cat ${BASE_DIR}/COPYRIGHT       | awk '{ print "#   " $0 }'       >> "${OUTFILE}" \
    && echo                                                              >> "${OUTFILE}" \
    && echo                                                              >> "${OUTFILE}"

    if [ ! -e "${OUTFILE}" ]; then
        failed_activity
        return 1
    fi

    # appending individual files
    for INPUTFILE in ${INPUTFILES}
    do
        echo "##### ${INPUTFILE} #####"                                  >> "${OUTFILE}" \
            && cat "${SRC_DIR}/${INPUTFILE}"      | grep -v "${SHEBANG}" >> "${OUTFILE}"
    done

    done_activity
}

function build() {
    begin_activity "Building"

    create_target_dirs
    copy_resources

    concat_scripts "${TARGET_DIR}/dist/pump.sh" \
        "common.sh" \
        "pump.sh" \
        "main.sh"

    concat_scripts "${TARGET_DIR}/dist/test.sh" \
        "common.sh" \
        "pump.sh" \
        "main-test.sh"

    done_activity
}

function main() {
    log_message '******************** GIT-SVN-PUMP BUILD SCRIPT STARTED  ********************'
    print_config && clean && build
    log_message '******************** GIT-SVN-PUMP BUILD SCRIPT COMPLETE ********************'
}

main
cd ${ORIGINAL_DIR}
