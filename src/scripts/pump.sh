#!/usr/bin/env bash

SVN_REPO=
SVN_PROXY_HOST=
SVN_PROXY_PORT=

OLD_DIR=$PWD
BASE_DIR=$PWD
PUMP_STATE_DIR=${PWD}/pump-state
PUMP_SVN_DIR=${PWD}/workdirs
PUMP_TEMP_DIR=${PWD}/tmp

SVN_CONFIG_FILE="${HOME}/.subversion/config"
SVN_MESSAGE_PREFIX='git-svn-pump:'
SVN_MESSAGE_GIT_INITIAL_COMMIT='initial_commit'
SVN_MESSAGE_GIT_COMMIT_PREFIX='git_commit_'

PUMPED_BRANCH_PATTERN1='^\s*v[0-9]\.[0-9]\.[0-9]_candidate$'
PUMPED_BRANCH_PATTERN2='^\s*svn_'
EXCLUDED_BRANCHES_PATTERN1='^\s*v0\.0\.0_candidate'
TAG_PREFIX=svnrev_
TEST_MODE=0
TEST_BRANCHES=""

SVN_OPTIONS=()
SVN_COMMAND_FORCE_LOG=0

GIT_BARE_REPO=${PWD}/repo.git

PUMP_CONFIG_FILE='pump.config'
PUMP_CONFIG_FILE_EXAMPLE="${PUMP_CONFIG_FILE}.example"

function svn_command() {
    SVN_COMMAND=$1
    shift
    if [ ${SVN_COMMAND_FORCE_LOG} -eq 1 ]; then
        echo '*' "Executing" "svn ${SVN_COMMAND} ${SVN_OPTIONS[@]} $@"
    fi
    svn ${SVN_COMMAND} ${SVN_OPTIONS[@]} $@ > /dev/null 2> /dev/null
}

function svn_command_unmuted() {
    SVN_COMMAND=$1
    shift
    svn ${SVN_COMMAND} ${SVN_OPTIONS[@]} $@
}

function git_command() {
    GIT_COMMAND=$1
    echo '*' "Executing" "git $@"
    git $@ > /dev/null 2> /dev/null
}

function git_command_unmuted() {
    GIT_COMMAND=$1
    git $@
}

function svn_connection_test() {
    echo Testing SVN connection...
    SVN_COMMAND_FORCE_LOG=1
    if ! svn_command info ${SVN_REPO}/trunk; then
        SVN_COMMAND_FORCE_LOG=0
        echo Testing SVN connection... [FAILED]
        return 1;
    fi
    SVN_COMMAND_FORCE_LOG=0
    echo Testing SVN connection... [OK]

    echo Checking SVN global-ignores...
    if [ ! -e ${SVN_CONFIG_FILE} ]; then
        echo SVN config file not found! ${SVN_CONFIG_FILE}
        echo Checking SVN global-ignores... [FAILED]
        return 1
    fi

    SVN_GLOBAL_IGNORES_EXISTS=$(echo $(cat ${SVN_CONFIG_FILE} |egrep '^global\-ignores\s*='|wc -l))
    SVN_GLOBAL_IGNORES=$(echo $(cat ${SVN_CONFIG_FILE} |egrep '^global\-ignores\s*='| awk -F '=' '{ print $2 }'))

    if [ ! ${SVN_GLOBAL_IGNORES_EXISTS} -eq "1" ]; then
        echo SVN config file ${SVN_CONFIG_FILE} should override default 'global-ignores' property
        echo Checking SVN global-ignores... [FAILED]
        return 1
    fi
    if [ -n "${SVN_GLOBAL_IGNORES}" ]; then
        echo SVN config file ${SVN_CONFIG_FILE} should override default 'global-ignores' property with empty string
        echo Checking SVN global-ignores... [FAILED]
        return 1
    fi

    echo Checking SVN global-ignores... [OK]
}

function svn_check_exists() {
    BRANCH=$1
    svn_command info ${SVN_REPO}/branches/${BRANCH}
}

function svn_create_branch() {
    local BRANCH=$1
    svn_command copy ${SVN_REPO}/trunk@1 ${SVN_REPO}/branches/${BRANCH} -m "generated_from_git_branch:${BRANCH}"
}

function svn_ensure_in_workdir_for_branch() {
    local BRANCH=$1
    WORKDIR=${PUMP_SVN_DIR}/${BRANCH}
    SUCCESS_MARKER=${PUMP_STATE_DIR}/branch_${BRANCH}

    if [ -e ${SUCCESS_MARKER} ]; then
        echo '*' Workdir for branch ${BRANCH} ready in ${WORKDIR}
        cd ${WORKDIR}
        return
    fi

    if [ -d ${WORKDIR} ]; then
        echo Backing up workdir ${WORKDIR} to ${WORKDIR}.bak
        rm -rf ${WORKDIR}.bak
        mv ${WORKDIR} ${WORKDIR}.bak
        echo Backing up workdir ${WORKDIR} to ${WORKDIR}.bak [DONE]
    fi

    if ! svn_check_exists ${BRANCH}; then
        echo There is no SVN branch ${BRANCH}, let\'s create it.
        if ! svn_create_branch ${BRANCH}; then
            echo SVN create branch failed!
            return 1;
        fi
        mkdir -p ${WORKDIR}
    else
        echo '*' SVN branch ${BRANCH} already exists, no need to create it
    fi

    echo Checking out branch ${BRANCH}...
    cd ${PUMP_SVN_DIR}
    if ! svn_command co ${SVN_REPO}/branches/${BRANCH}; then
        echo SVN checkout failed!
        return 1;
    fi
    echo Checking out branch ${BRANCH}... [DONE]

    cd ${WORKDIR}

    echo SVN-updating branch ${BRANCH}...
    if ! svn_command update; then
        echo SVN update failed!
        return 1;
    fi
    echo SVN-updating branch ${BRANCH}... [DONE]

    touch ${SUCCESS_MARKER}
}

function ensure_local_git_repo_exists_for_branch() {
    local BRANCH=$1
    GIT_CLONE_SUCCESS_MARKER=${PUMP_STATE_DIR}/gitclone_${BRANCH}

    if [ -e ${GIT_CLONE_SUCCESS_MARKER} ]; then
        echo '*' local git repo for branch ${BRANCH} exists, skipping
        return
    fi

    echo local git repo for branch ${BRANCH} does not exist yet! Creating it by cloning into a separate folder...

    if ! git_command clone -b ${BRANCH} ${GIT_BARE_REPO} local_git_repo; then
        echo git clone failed for branch ${BRANCH}
        return 1
    fi

    echo local git repo for branch ${BRANCH} does not exist yet! Creating it by cloning into a separate folder... [DONE]

    touch ${GIT_CLONE_SUCCESS_MARKER}
}

function ensure_svnignore_setup() {
    BASIC_SVNIGNORE_FILE=${BASE_DIR}/basic_svnignore
    BASIC_GITIGNORE_FILE=${BASE_DIR}/basic_gitignore
    svn_command_unmuted propget svn:ignore | cat ${BASIC_SVNIGNORE_FILE} - | grep -v '^#' | grep -v -e '^\s*$' | sort -u | svn_command propset svn:ignore -F - .
    if [ ! $? -eq 0 ]; then
        echo svn:ignore setup failed!
        return 1
    fi

    echo Excluding .svn dirs through .gitignore...
    touch .gitignore && cat .gitignore ${BASIC_GITIGNORE_FILE} | grep -v '^#' | grep -v -e '^\s*$' | sort -u > .gitignore.new && mv .gitignore.new .gitignore
    if [ ! $? -eq 0 ]; then
        echo An error has occurred while manipulating .gitignore file
        return 1
    fi
    echo Excluding .svn dirs through .gitignore... [DONE]
}

function svn_prepare_for_commit() {
    svn_command cleanup .
    if [ ! $? -eq 0 ]; then
        echo Failed svn cleanup command!
        return 1
    fi

    N_TO_REMOVE=$(svn_command_unmuted status | grep '^[\!\~]' | sed 's/^[\!\~] *//g' | wc -l)
    N_TO_ADD=$(svn_command_unmuted status | grep '^[\?\~]' | sed 's/^[\?\~] *//g' | wc -l)

    echo '*' Items to remove from SVN: ${N_TO_REMOVE}
    echo '*' Items to add to SVN: ${N_TO_ADD}

    if [ ${N_TO_REMOVE} -gt 0 ]; then
        svn_command_unmuted status | grep '^[\!\~]' | sed 's/^[\!\~] *//g' | xargs -d \\n svn rm > /dev/null 2> /dev/null
        if [ ! $? -eq 0 ]; then
            echo Failed svn rm command!
            return 1
        fi
    fi

    if [ ${N_TO_ADD} -gt 0 ]; then
        svn_command_unmuted status | grep '^[\?\~]' | sed 's/^[\?\~] *//g' | xargs -d \\n svn add > /dev/null 2> /dev/null
        if [ ! $? -eq 0 ]; then
            echo Failed svn add command!
            return 1
        fi
    fi

    L=$(svn_command_unmuted status | grep '^[\?\!]' | wc -l)
    if [ ! ${L} -eq 0 ]; then
        echo SVN commit preparation check failed!
        return 1
    fi
}

function ensure_initial_svn_commit_for_git_branch() {
    local BRANCH=$1
    INITIAL_SVN_COMMIT_SUCCESS_MARKER=${PUMP_STATE_DIR}/initialSvnCommit_${BRANCH}
    
    if [ -e ${INITIAL_SVN_COMMIT_SUCCESS_MARKER} ]; then
        echo '*' skipping initial svn commit
        return
    fi

    if [ -d local_git_repo/.git ]; then
        echo moving git metadata to svn working folder...

        mv local_git_repo/.git .git
        if [ ! $? -eq 0 ]; then
            echo Error while moving git metadata to svn working folder!
            return 1
        fi

        echo moving git metadata to svn working folder... [DONE]
    fi

    rm -rf local_git_repo
    if [ ! $? -eq 0 ]; then
        echo Error while deleting separate git folder!
        return 1
    fi

    echo resetting git/svn shared working folder to git-controlled state...
    if ! git_command reset --hard; then
        echo Failed git reset --hard command!
        return 1
    fi
    #removing residual untracked files (those which where present on svn, but not on git)
    if ! git_command clean -fd; then
        echo Failed git clean command!
        return 1
    fi
    echo resetting git/svn shared working folder to git-controlled state... [DONE]

    if ! svn_prepare_for_commit; then
        return 1
    fi

    echo Performing SVN initial commit...
    SVN_COMMIT_MESSAGE="${SVN_MESSAGE_PREFIX}${SVN_MESSAGE_GIT_INITIAL_COMMIT}"
    if ! svn_command commit -m ${SVN_COMMIT_MESSAGE}; then
        echo SVN commit failed!
        return 1
    fi
    echo Performing SVN initial commit... [DONE]

    touch ${INITIAL_SVN_COMMIT_SUCCESS_MARKER}
}

function ensure_git_tag_for_svn_revision() {
    EXPECTED_GIT_COMMIT_ID=$1

    SVN_REV=$(svn_command_unmuted log -rHEAD:BASE -q|egrep -v '^---'|head -n 1| awk '{ print $1 }'|sed 's/r//g')
    if [ ! $? -eq 0 ]; then
        echo Could not retrieve current SVN revision!
        return 1
    fi

    echo '*' SVN Revision: ${SVN_REV}

    IN_SYNC_WITH_GIT=0
    if [ -z "$(git status --porcelain)" ]; then
      # Working directory clean
      IN_SYNC_WITH_GIT=1
    else
      # Uncommitted changes
      IN_SYNC_WITH_GIT=0
    fi
    if [ ! $? -eq 0 ]; then
        echo "Could not check whether the working folder is actually in-sync with the local git repo!"
        return 1
    fi

    if [ -n "${EXPECTED_GIT_COMMIT_ID}" ]; then
        SVN_MESSAGE_LINE=$(svn_command_unmuted log -rHEAD:BASE -l 1 --incremental|tail -n+4|egrep "^${SVN_MESSAGE_PREFIX}")
        if [ ! $? -eq 0 ]; then
            echo "Could not retrieve SVN message for last commit, message check failed!"
            return 1
        fi

        SVN_REPORTED_GIT_COMMIT=$(echo "${SVN_MESSAGE_LINE}" | sed "s/${SVN_MESSAGE_PREFIX}${SVN_MESSAGE_GIT_COMMIT_PREFIX}//g")

        if [ ${EXPECTED_GIT_COMMIT_ID} != ${SVN_REPORTED_GIT_COMMIT} ]; then
            echo "Refused to add svn revision number as git tag: svn commit message mismatch!"
            return 1
        fi
    fi

    if [ ! ${IN_SYNC_WITH_GIT} -eq 1 ]; then
        echo Refused to add svn revision number as git tag: the working folder in not in-sync with the git repo
        return 1
    fi

    TAG_NAME=${TAG_PREFIX}${SVN_REV}
    TAG_EXISTS=$(git tag | grep ${TAG_NAME} | wc -l)
    if [ ${TAG_EXISTS} -eq 0 ]; then
        echo Creating git tag ${TAG_NAME}...
        if ! git_command tag ${TAG_NAME}; then
            echo Tag creation failed!
            return 1
        fi
        echo Creating git tag ${TAG_NAME}... [DONE]
        else
        echo '*' git tag ${TAG_NAME} found
    fi
}

function process_unpumped_commit() {
    local BRANCH=$1
    shift
    local COMMIT_ID=$1
    shift

    echo Processing unpumped commit ${COMMIT_ID}...

    if ! git_command checkout -f --detach ${COMMIT_ID}; then
        echo Failed to checkout git commit ${COMMIT_ID}
        return 1;
    fi

    #removing residual untracked files
    if ! git_command clean -fd; then
        echo Failed git clean command!
        return 1
    fi

    if ! svn_prepare_for_commit; then
        return 1
    fi

    COMMIT_MESSAGE_FILE="${PUMP_TEMP_DIR}/svn_commit_message.${COMMIT_ID}"
    git log -n 1 --pretty='format:%B' ${COMMIT_ID} > ${COMMIT_MESSAGE_FILE}
    if [ ! $? -eq 0 ]; then
        echo Could not save git commit message to file!
        return 1
    fi

    SVN_COMMIT_MESSAGE="${SVN_MESSAGE_PREFIX}${SVN_MESSAGE_GIT_COMMIT_PREFIX}${COMMIT_ID}"
    echo >> ${COMMIT_MESSAGE_FILE}
    echo "${SVN_COMMIT_MESSAGE}" >> ${COMMIT_MESSAGE_FILE}
    echo '*' Commit message file: ${COMMIT_MESSAGE_FILE}

    echo Performing SVN pump commit...

    if ! svn_command commit -F ${COMMIT_MESSAGE_FILE}; then
        echo SVN commit failed!
        return 1
    fi
    echo Performing SVN pump commit... [DONE]

    if ! ensure_git_tag_for_svn_revision; then
        return 1;
    fi

    if ! git_command checkout -B ${BRANCH} ${COMMIT_ID}; then
        echo Failed to force git branch ${BRANCH} to commit ${COMMIT_ID}
        return 1
    fi

    echo Processing unpumped commit ${COMMIT_ID}... [DONE]
}

function process_branch() {
    local BRANCH=$1

    if ! svn_ensure_in_workdir_for_branch ${BRANCH}; then
        return 1;
    fi

    echo Ensuring local git repo exists for branch ${BRANCH}...
    if ! ensure_local_git_repo_exists_for_branch ${BRANCH}; then
        return 1;
    fi
    echo Ensuring local git repo exists for branch ${BRANCH}... [DONE]

    if ! ensure_svnignore_setup; then
        return 1;
    fi

    if ! ensure_initial_svn_commit_for_git_branch ${BRANCH}; then
        return 1;
    fi

    if ! ensure_git_tag_for_svn_revision; then
        return 1;
    fi

    if ! git_command remote update origin --prune; then
        echo Failed to update branch local git repo
        return 1
    fi

    #preparing list of "unpumped" git commits
    COMMIT_LIST=()
    readarray COMMIT_LIST < <(git log --no-decorate --format=oneline --ancestry-path --reverse ${BRANCH}..origin/${BRANCH})

    #print out the commit list
    N_UNPUMPED_COMMITS=${#COMMIT_LIST[@]}
    echo "BEGIN list of unpumped commits: (size=$N_UNPUMPED_COMMITS)"
    for COMMIT_INFO in "${COMMIT_LIST[@]}"; do
        echo '*' "New commit:" ${COMMIT_INFO}
    done
    echo "END list of unpumped commits: (size=$N_UNPUMPED_COMMITS)"

    for COMMIT_INFO in "${COMMIT_LIST[@]}"; do
        COMMIT_ID=$(echo ${COMMIT_INFO} | awk '{ print $1 }')
        if ! process_unpumped_commit ${BRANCH} ${COMMIT_ID} ; then
            return 2
        fi
    done

    if ! git_command push origin '--tags' ; then
        echo "'Failed pushing svnrev_*' tags for branch ${BRANCH} to git-svn-pump main repo"
        return 1
    fi
}

function sync() {
    echo Fetching...
    git fetch --all

    echo 'Checking for new branches...'
    local BRANCHES_1=$(git branch|egrep ${PUMPED_BRANCH_PATTERN1}|egrep -v ${EXCLUDED_BRANCHES_PATTERN1})
    local BRANCHES_2=$(git branch|egrep ${PUMPED_BRANCH_PATTERN2})

    local S_ALL_BRANCHES="${BRANCHES_1} ${BRANCHES_2}"

    echo 'Branches:'
    echo ${S_ALL_BRANCHES}

    if [ ${TEST_MODE} -eq 1 ]; then
        echo Test mode: overriding branches...
        S_ALL_BRANCHES=${TEST_BRANCHES}

        echo 'Branches:'
        echo ${S_ALL_BRANCHES}
    fi

    local ALL_BRANCHES=()
    read -r -a ALL_BRANCHES <<< ${S_ALL_BRANCHES}

    echo Branch count: ${#ALL_BRANCHES[@]}

    for BRANCH in "${ALL_BRANCHES[@]}"; do
        echo Processing branch ${BRANCH}

        if ! process_branch ${BRANCH}; then
            echo Continuing with next branch, if any
        fi
    done

    echo 'Pushing svnrev_* tags...'
    cd ${GIT_BARE_REPO}
    if ! git_command push; then
        echo Could not push 'svnrev_*' tags to upstream git repository
        return 1
    fi
    echo 'Pushing svnrev_* tags...' [DONE]
}

function ensure_git_bare_repo() {
    GIT_BARE_REPO_CLONE_SUCCESS_MARKER=${PUMP_STATE_DIR}/gitbarerepo_clone
    if [ -e GIT_BARE_REPO_CLONE_SUCCESS_MARKER ]; then
        echo '*' bare git repo already cloned, skipping
        return 0
    fi

    echo 'bare git repo does not exist yet! Creating it by cloning root git repo...'
    if ! git_command clone --mirror ${GIT_ROOT_URL} ${GIT_BARE_REPO}; then
        echo 'Failed git clone!'
        cd ${BASE_DIR}
        rm -rf ${GIT_BARE_REPO}
        return 1;
    fi
    touch ${GIT_BARE_REPO_CLONE_SUCCESS_MARKER}
    echo 'bare git repo does not exist yet! Creating it by cloning root git repo... [DONE]'
}

function load_config() {
    if [ -e "${PUMP_CONFIG_FILE}" ]; then
        echo "Loading configuration..."
        . "${PUMP_CONFIG_FILE}"
        echo "GIT_BARE_REPO: ${GIT_BARE_REPO}"
        echo "SVN_REPO: ${SVN_REPO}"

        if [ "${SVN_PROXY_HOST}:${SVN_PROXY_PORT}" == ":" ]; then
            echo "SVN proxy: <none>"
            SVN_OPTIONS=( '--config-option' "servers:global:http-proxy-host=${SVN_PROXY_HOST}" '--config-option' "servers:global:http-proxy-port=${SVN_PROXY_PORT}")
        else
            echo "SVN proxy: ${SVN_PROXY_HOST}:${SVN_PROXY_PORT}"
            SVN_OPTIONS=( '--config-option' "servers:global:http-proxy-host=${SVN_PROXY_HOST}" '--config-option' "servers:global:http-proxy-port=${SVN_PROXY_PORT}")
        fi
        echo "Loading configuration... [DONE]"
    else
        echo "ERROR: ${PUMP_CONFIG_FILE} not found!"
        echo "Please configure git-svn-pump first. See ${PUMP_CONFIG_FILE_EXAMPLE} for more info."
        return 1
    fi

    if [ "$GIT_BARE_REPO" == "" ]; then
        echo "ERROR: GIT_BARE_REPO undefined in configuration!"
        return 1
    fi

    if [ "$SVN_REPO" == "" ]; then
        echo "ERROR: SVN_REPO undefined in configuration!"
        return 1
    fi
}

function main() {
    if ! load_config; then
        return 1;
    fi

    cd ${BASE_DIR}
    mkdir -p ${PUMP_STATE_DIR}
    mkdir -p ${PUMP_SVN_DIR}
    mkdir -p ${PUMP_TEMP_DIR}

    ensure_git_bare_repo

    cd ${GIT_BARE_REPO}

    if svn_connection_test; then
        sync
    fi

    cd ${OLD_DIR}
}
