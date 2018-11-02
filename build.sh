#!/usr/bin/env bash

. src/scripts/common.sh

ORIGINAL_DIR=${PWD}

BASE_DIR=${PWD}
SRC_DIR=${BASE_DIR}/src/scripts
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

function set_executable() {
    local FILE=$1
    begin_activity "Setting as executable: ${FILE}"

    chmod +x "${FILE}"

    if ! [[ -x "${FILE}" ]]; then
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
        echo "##### module ${INPUTFILE} #####"                                  >> "${OUTFILE}" \
            && cat "${SRC_DIR}/${INPUTFILE}"      | grep -v "${SHEBANG}" >> "${OUTFILE}"
    done

    set_executable "${OUTFILE}"

    done_activity
}

function create_target_archive() {
    local OUTFILE=$1
    local ROOT_FOLDER_IN_ARCHIVE=$2
    local ARCHIVE_SOURCE=$3

    begin_activity "Creating archive ${OUTFILE}"

    cd "${ARCHIVE_SOURCE}" \
    && tar -cvzf "${OUTFILE}" --transform "s/^\./${ROOT_FOLDER_IN_ARCHIVE}/" .

    cd "${BASE_DIR}"

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

    create_target_archive "${TARGET_DIR}/git-svn-pump.tgz" "git-svn-pump-instance" "${TARGET_DIR}/dist"

    done_activity
}

function main() {
    log_message '******************** GIT-SVN-PUMP BUILD SCRIPT STARTED  ********************'
    print_config && clean && build
    log_message '******************** GIT-SVN-PUMP BUILD SCRIPT COMPLETE ********************'
}

main
cd ${ORIGINAL_DIR}
