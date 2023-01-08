#!/usr/bin/env bash
#==============================================================================================
#
# Function: Delete older releases and workflow runs
# Copyright (C) 2023- https://github.com/ophub/delete-releases-workflows
# Use api.github.com official documentation
# https://docs.github.com/en/rest/releases/releases?list-releases
# https://docs.github.com/en/rest/actions/workflow-runs?list-workflow-runs-for-a-repository
#
#======================================= Functions list =======================================
#
# error_msg           : Output error message
# init_var            : Initialize all variables
# get_releases_list   : Get the release list
# del_release_tag     : Delete releases and tags
# get_workflows_list  : Get the workflows list
# del_workflows_runs  : Delete workflows runs
#
#=============================== Set make environment variables ===============================
#
# Set font color
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
TIPS="[\033[93m TIPS \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
#
#==============================================================================================

error_msg() {
    echo -e "${ERROR} ${1}"
    exit 1
}

init_var() {
    echo -e "${STEPS} Start Initializing Variables..."

    # Install the necessary dependent packages
    sudo apt-get -qq update && sudo apt-get -qq install -y jq

    # If it is followed by [ : ], it means that the option requires a parameter value
    get_all_ver="$(getopt "r:t:l:w:k:d:g:" "${@}")"

    while [[ -n "${1}" ]]; do
        case "${1}" in
        -r | --repo)
            if [[ -n "${2}" ]]; then
                repo="${2}"
                shift
            else
                error_msg "Invalid -r parameter [ ${2} ]!"
            fi
            ;;
        -t | --delete_tags)
            if [[ -n "${2}" ]]; then
                delete_tags="${2}"
                shift
            else
                error_msg "Invalid -t parameter [ ${2} ]!"
            fi
            ;;
        -l | --releases_keep_latest)
            if [[ -n "${2}" ]]; then
                releases_keep_latest="${2}"
                shift
            else
                error_msg "Invalid -l parameter [ ${2} ]!"
            fi
            ;;
        -w | --releases_keep_keyword)
            if [[ -n "${2}" ]]; then
                releases_keep_keyword="${2}"
                shift
            else
                error_msg "Invalid -w parameter [ ${2} ]!"
            fi
            ;;

        -k | --workflows_keep_keyword)
            if [[ -n "${2}" ]]; then
                workflows_keep_keyword="${2}"
                shift
            else
                error_msg "Invalid -k parameter [ ${2} ]!"
            fi
            ;;
        -d | --workflows_keep_day)
            if [[ -n "${2}" ]]; then
                workflows_keep_day="${2}"
                shift
            else
                error_msg "Invalid -d parameter [ ${2} ]!"
            fi
            ;;
        -g | --gh_token)
            if [[ -n "${2}" ]]; then
                gh_token="${2}"
                shift
            else
                error_msg "Invalid -g parameter [ ${2} ]!"
            fi
            ;;
        *)
            error_msg "Invalid option [ ${1} ]!"
            ;;
        esac
        shift
    done

    echo -e "${INFO} repo: [ ${repo} ]"
    echo -e "${INFO} delete_tags: [ ${delete_tags} ]"
    echo -e "${INFO} releases_keep_latest: [ ${releases_keep_latest} ]"
    echo -e "${INFO} releases_keep_keyword: [ ${releases_keep_keyword} ]"
    echo -e "${INFO} workflows_keep_keyword: [ ${workflows_keep_keyword} ]"
    echo -e "${INFO} workflows_keep_day: [ ${workflows_keep_day} ]"
    echo -e ""
}

get_releases_list() {
    echo -e "${STEPS} Start generating the releases list..."

    # Temporary save file for the results returned by the github API for releases
    gh_api_releases="josn_api_releases"
    curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${gh_token}" \
        https://api.github.com/repos/${repo}/releases \
        >${gh_api_releases}
    [[ -s "${gh_api_releases}" ]] || error_msg "(1.1) The api.github.com for releases query failed."
    echo -e "${INFO} (1.1) github API for releases request succeeded."

    # All lists in releases
    all_releases_list="josn_all_releases_list"
    cat ${gh_api_releases} | jq -c '.[] | {pub_date: .published_at, id: .id, name: .name, tag_name: .tag_name}' >${all_releases_list}
    if [[ -s "${all_releases_list}" ]]; then
        echo -e "${INFO} (1.2) All releases lists are generated successfully. Current list:\n$(cat ${all_releases_list})"
    else
        echo -e "${TIPS} (1.2) The releases list is empty."
    fi

    # List of releases keywords to keep
    keep_releases_keyword_list="josn_keep_releases_keyword_list"
    # Remove releases that match keywords and need to be kept
    if [[ -n "${releases_keep_keyword}" && -s "${all_releases_list}" ]]; then
        cat ${all_releases_list} | jq -r .name | grep ${releases_keep_keyword} >${keep_releases_keyword_list}
        [[ -s "${keep_releases_keyword_list}" ]] && cat ${keep_releases_keyword_list} | while read line; do sed -i "/${line}/d" ${all_releases_list}; done
        echo -e "${INFO} (1.3) Keep keyword list filtered successfully. Current list:\n$(cat ${all_releases_list})"
    else
        echo -e "${TIPS} (1.3) Skip keep keyword releases filtering."
    fi

    # List of releases date to keep
    keep_releases_date_list="josn_keep_releases_date_list"
    # List of releases to keep
    keep_releases_list="josn_keep_releases_list"
    # Sort and generate a keep list of releases
    if [[ -s "${all_releases_list}" && -n "${releases_keep_latest}" ]]; then
        cat ${all_releases_list} | jq -r '.pub_date' | tr ' ' '\n' | sort -r | head -${releases_keep_latest} >${keep_releases_date_list}
        cat ${keep_releases_date_list} | while read line; do grep "${line}" ${all_releases_list} >>${keep_releases_list}; done
        echo -e "${INFO} (1.4) The keep releases list is generated successfully. Keep list:\n$(cat ${keep_releases_list})"
    else
        echo -e "${TIPS} (1.4) The releases list is empty. skip."
    fi

    # Remove the keep_releases_list from all_releases_list
    if [[ -s "${keep_releases_date_list}" ]]; then
        cat ${keep_releases_date_list} | while read line; do sed -i "/${line}/d" ${all_releases_list}; done
        echo -e "${INFO} (1.5) Need to keep list filtered successfully."
    else
        echo -e "${TIPS} (1.5) The keep list is empty. skip."
    fi

    # The list to be deleted in releases
    del_releases_list="josn_del_releases_list"
    # Generate releases.id delete list
    if [[ -s "${all_releases_list}" ]]; then
        cat ${all_releases_list} >${del_releases_list}
        echo -e "${SUCCESS} (1.6) Delete releases list generated successfully. Delete list:\n$(cat ${del_releases_list})"
    else
        echo -e "${TIPS} (1.6) The delete releases list is empty. skip."
    fi

    echo -e ""
}

del_release_tag() {
    echo -e "${STEPS} Start deleting releases and tags..."

    # Delete releases
    if [[ -s "${del_releases_list}" && -n "$(cat ${del_releases_list} | jq -r .id)" ]]; then
        cat ${del_releases_list} | jq -r .id | while read release_id; do
            {
                curl -s \
                    -X DELETE \
                    -H "Accept: application/vnd.github+json" \
                    -H "Authorization: Bearer ${gh_token}" \
                    https://api.github.com/repos/${repo}/releases/${release_id}
            }
        done
        echo -e "${SUCCESS} (2.1) Releases deleted successfully."
    else
        echo -e "${TIPS} (2.1) No releases need to be deleted. skip."
    fi

    # Delete the tags associated with releases
    if [[ "${delete_tags}" = "true" && -s "${del_releases_list}" && -n "$(cat ${del_releases_list} | jq -r .tag_name)" ]]; then
        cat ${del_releases_list} | jq -r .tag_name | while read tag_name; do
            {
                curl -s \
                    -X DELETE \
                    -H "Accept: application/vnd.github+json" \
                    -H "Authorization: Bearer ${gh_token}" \
                    https://api.github.com/repos/${repo}/git/refs/tags/${tag_name}
            }
        done
        echo -e "${SUCCESS} (2.2) Tags deleted successfully."
    else
        echo -e "${TIPS} (2.2) No tags need to be deleted. skip."
    fi

    echo -e ""
}

get_workflows_list() {
    echo -e "${STEPS} Start generating the workflows list..."

    # Temporary save file for the results returned by the github API for workflows runs
    gh_api_workflows="josn_api_workflows"
    curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${gh_token}" \
        https://api.github.com/repos/${repo}/actions/runs \
        >${gh_api_workflows}
    [[ -s "${gh_api_workflows}" ]] || error_msg "(3.1) The api.github.com for workflows query failed."
    echo -e "${INFO} (3.1) github API for workflows request succeeded."

    # All lists in workflows
    all_workflows_list="josn_all_workflows_list"
    cat ${gh_api_workflows} | jq -c '.workflow_runs[] | {pub_date: .updated_at, id: .id, name: .name}' >${all_workflows_list}
    if [[ -s "${all_workflows_list}" ]]; then
        echo -e "${INFO} (3.2) All workflows lists are generated successfully. Current list:\n$(cat ${all_workflows_list})"
    else
        echo -e "${TIPS} (3.2) The workflows list is empty."
    fi

    # The workflows containing keywords that need to be keep
    keep_keyword_workflows_list="josn_keep_keyword_workflows_list"
    # Remove workflows that match keywords and need to be kept
    if [[ -n "${workflows_keep_keyword}" && -s "${all_workflows_list}" ]]; then
        cat ${all_workflows_list} | jq -r .name | grep ${workflows_keep_keyword} >${keep_keyword_workflows_list}
        [[ -s "${keep_keyword_workflows_list}" ]] && cat ${keep_keyword_workflows_list} | while read line; do sed -i "/${line}/d" ${all_workflows_list}; done
        echo -e "${INFO} (3.3) Keep keyword list filtered successfully. Current list:\n$(cat ${all_workflows_list})"
    else
        echo -e "${TIPS} (3.3) Skip keep keyword workflows filtering."
    fi

    # Generate a date list of workflows
    all_workflows_date_list="josn_all_workflows_date_list"
    # Generate a keep list of workflows
    keep_workflows_list="josn_keep_workflows_list"
    # Temporary josn file
    tmp_josn_file="$(mktemp)"
    # Sort and generate a keep list of workflows
    if [[ -s "${all_workflows_list}" && -n "${workflows_keep_day}" ]]; then
        today_second=$(date -d "$(date +"%Y%m%d")" +%s)
        cat ${all_workflows_list} | jq -r '.pub_date' | awk -F'T' '{print $1}' | tr ' ' '\n' >${all_workflows_date_list}
        cat ${all_workflows_date_list} | while read line; do
            line_second="$(date -d "${line//-/}" +%s)"
            day_diff="$(((${today_second} - ${line_second}) / 86400))"
            [[ "${day_diff}" -le "${workflows_keep_day}" ]] && {
                grep "${line}T" ${all_workflows_list} >>${keep_workflows_list}
                sed -i "/${line}T/d" ${all_workflows_list}
            }
        done
        # Remove duplicate lines
        awk '!a[$0]++' ${keep_workflows_list} >${tmp_josn_file} && mv -f ${tmp_josn_file} ${keep_workflows_list}
        echo -e "${INFO} (3.4) The keep workflows list is generated successfully. Keep list:\n$(cat ${keep_workflows_list})"
    else
        echo -e "${TIPS} (3.4) The workflows list is empty. skip."
    fi

    # The list to be deleted in workflows
    del_workflows_list="josn_del_workflows_list"
    # Generate workflows.id delete list
    if [[ -s "${all_workflows_list}" ]]; then
        cat ${all_workflows_list} >${del_workflows_list}
        echo -e "${SUCCESS} (3.5) Delete workflows list generated successfully. Delete list:\n$(cat ${del_workflows_list})"
    else
        echo -e "${TIPS} (3.5) The delete workflows list is empty. skip."
    fi

    echo -e ""
}

del_workflows_runs() {
    echo -e "${STEPS} Start deleting workflows runs..."

    # Delete workflows runs
    if [[ -s "${del_workflows_list}" && -n "$(cat ${del_workflows_list} | jq -r .id)" ]]; then
        cat ${del_workflows_list} | jq -r .id | while read workflows_id; do
            {
                curl -s \
                    -X DELETE \
                    -H "Accept: application/vnd.github+json" \
                    -H "Authorization: Bearer ${gh_token}" \
                    https://api.github.com/repos/${repo}/actions/runs/${workflows_id}
            }
        done
        echo -e "${SUCCESS} (4.1) Workflows runs deleted successfully."
    else
        echo -e "${TIPS} (4.1) No Workflows runs need to be deleted. skip."
    fi

    echo -e ""
}

# Show welcome message
echo -e "${STEPS} Welcome to use the delete older releases and workflow runs tool!"

# Perform related operations in sequence
init_var "${@}"
get_releases_list
del_release_tag
get_workflows_list
del_workflows_runs

# Show all process completion prompts
echo -e "${SUCCESS} All process completed successfully."
wait