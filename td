#!/usr/bin/env bash

##
# td
# Context-aware todo list manager

# handle debugging
if [[ "${TRACE-0}" == "1" ]]; then set -o xtrace; fi

# Vars
CONFIG_DIR="${XDG_CONFIG_HOME:=${HOME}/.config}/todo"
CONFIG_FILE="todorc"
TODO_LIST="${CONFIG_DIR}/todo.lst"

# Colors
NC='\033[0m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[1;30m'
CYAN='\033[0;36m'

# Config defaults
DEFAULT_ACTION=help
PRESERVE_QUEUE=false
QUEUE_MODE=lifo
PROJECTS_ONLY=false

# --- Functions ---

function show_help {
    echo -e "${BLUE}Usage: td [cmd] [args]${NC}"
    echo -e "  a, push [f] MSG   Add task (short for 'add')"
    echo -e "  l, list           List tasks with paths"
    echo -e "  n, next, do       Take the next task (pop)"
    echo -e "  rm <N>            Remove task number <N>"
    echo -e "  c, clear          Clear all"
    echo -e "  h, help           Show this help"
    echo -e "\n${GRAY}Implicit push: 'td fix bug' = 'td a fix bug'${NC}"
}

function config_if_needed {
    if [[ ! -d ${CONFIG_DIR} ]]; then mkdir -p "${CONFIG_DIR}"; fi
    if [[ ! -s ${CONFIG_DIR}/${CONFIG_FILE} ]]; then
        { echo "DEFAULT_ACTION=${DEFAULT_ACTION}"; echo "PRESERVE_QUEUE=${PRESERVE_QUEUE}";
          echo "PROJECTS_ONLY=${PROJECTS_ONLY}"; echo "QUEUE_MODE=${QUEUE_MODE}"; } > "${CONFIG_DIR}/${CONFIG_FILE}"
    fi
    source "${CONFIG_DIR}/${CONFIG_FILE}"
}

function push_to_stack {
    local _file=""
    if [[ -f "$1" ]]; then
        _file="$1"
        shift
    fi
    local _msg="$*"

    if [[ -z "${_msg}" ]]; then
        echo -e "${RED}Error: Empty message.${NC}"
        exit 1
    fi

    _toplevel=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
    # ~TIMESTAMP~DIR~FILE~MSG~
    echo "~$(date +%s)~${_toplevel}~${_file}~${_msg}~" >> "${TODO_LIST}"
    echo -e "${BLUE}Saved.${NC} [$(wc -l "${TODO_LIST}" | cut -d' ' -f1)]"
}

function find_when {
    if [[ $(uname -s) == "Darwin" ]]; then
        WHEN="$(date -j -f %s "$1" "+%m-%d %H:%M")"
    else
        WHEN="$(date --date "@$1" "+%m-%d %H:%M")"
    fi
}

function show_todos {
    if [[ ! -s "${TODO_LIST}" ]]; then
        echo -e "${GRAY}Empty.${NC}"; return
    fi

    printf "${GRAY}%-3s %-12s %-15s %s${NC}\n" "ID" "Date" "File" "Task"
    
    local counter=1
    while read -r LINE; do
        _WHEN=$(echo "${LINE}" | cut -d~ -f2)
        WHERE=$(echo "${LINE}" | cut -d~ -f3)
        FILE=$(echo "${LINE}" | cut -d~ -f4)
        WHAT=$(echo "${LINE}" | cut -d~ -f5)
        
        DISPLAY_WHERE="${WHERE/#$HOME/\~}"
        
        if [[ -n "${FILE}" ]]; then
            DISPLAY_FILE="${YELLOW}${FILE}${NC}"
        else
            DISPLAY_FILE="${GRAY}--${NC}"
        fi

        find_when "${_WHEN}"
        
        printf "${GREEN}%-3s${NC} %-12s %-15b %s ${CYAN}(%s)${NC}\n" \
            "${counter}" "${WHEN}" "${DISPLAY_FILE}" "${WHAT}" "${DISPLAY_WHERE}"
            
        ((counter++))
    done < "${TODO_LIST}"
}

function delete_todo {
    local id="$1"
    if [[ -z "$id" ]] || ! [[ "$id" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Use number (e.g., td rm 2)${NC}"
        exit 1
    fi

    local total
    total=$(wc -l < "${TODO_LIST}")

    if (( id > total )) || (( id < 1 )); then
        echo -e "${RED}Error: Task $id not found.${NC}"
        exit 1
    fi

    local line_content
    line_content=$(sed "${id}q;d" "${TODO_LIST}")
    local what=$(echo "${line_content}" | cut -d~ -f5)

    if [[ $(uname -s) == "Darwin" ]]; then
        sed -i '' "${id}d" "${TODO_LIST}"
    else
        sed -i "${id}d" "${TODO_LIST}"
    fi

    echo -e "${RED}Deleted ($id):${NC} $what"
}

function pop_from_stack {
    TODOS=$(wc -l "${TODO_LIST}" 2>/dev/null | cut -d' ' -f1)
    if [[ ${TODOS} -lt 1 ]]; then echo -e "${BLUE}Done!${NC}"; exit 0; fi

    _toplevel=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
    
    [[ "${QUEUE_MODE}" == "lifo" ]] && CMD="tail" || CMD="head"

    LINE=$(grep "~${_toplevel}~" "${TODO_LIST}" | $CMD -n 1)
    if [[ "${PROJECTS_ONLY}" == 'false' ]] && [[ -z "${LINE}" ]]; then
        LINE=$($CMD -n 1 "${TODO_LIST}")
    fi

    if [[ -z "${LINE}" ]]; then echo -e "${BLUE}No context todos.${NC}"; exit 0; fi

    RAW_TS=$(echo "${LINE}" | cut -d~ -f2)
    WHERE=$(echo "${LINE}" | cut -d~ -f3)
    FILE=$(echo "${LINE}" | cut -d~ -f4)
    WHAT=$(echo "${LINE}" | cut -d~ -f5)

    DISPLAY_WHERE="${WHERE/#$HOME/\~}"

    echo -e "${GREEN}>>> NEXT TASK:${NC} ${WHAT}"
    
    if [[ "${WHERE}" != "${PWD}" ]]; then
        echo -e "${GRAY}Dir:${NC}  cd ${DISPLAY_WHERE}"
    else
        echo -e "${GRAY}Dir:${NC}  (Current directory)"
    fi

    if [[ -n "${FILE}" ]]; then
        echo -e "${GRAY}File:${NC} ${YELLOW}${FILE}${NC}"
        if [[ -n "${EDITOR}" ]]; then
             echo -e "${GRAY}Cmd:${NC}  ${EDITOR} ${FILE}"
        fi
    fi

    if [[ "${PRESERVE_QUEUE}" == 'false' ]]; then
        if [[ $(uname -s) == "Darwin" ]]; then
            sed -i '' "/^~${RAW_TS}~/d" "${TODO_LIST}"
        else
            sed -i "/^~${RAW_TS}~/d" "${TODO_LIST}"
        fi
    fi
}

# --- Main Logic ---

if [[ $# -eq 0 ]]; then
    show_todos
    exit 0
fi

CMD=$1
shift

case "$CMD" in
    l|list|ls)
        show_todos
        ;;
    n|next|do|pop|pp)
        config_if_needed
        pop_from_stack
        ;;
    rm|del|delete)
        config_if_needed
        delete_todo "$1"
        ;;
    c|clear)
        > "${TODO_LIST}"
        echo -e "${BLUE}Cleared.${NC}"
        ;;
    a|add|p|push)
        config_if_needed
        push_to_stack "$@"
        ;;
    h|help|--help)
        show_help
        exit 0
        ;;
    *)
        # If the command is not recognized, we consider it to be the task text. 
        if [[ -n "$CMD" ]]; then
             config_if_needed
             push_to_stack "$CMD" "$@"
             exit 0
        fi
        show_help
        exit 1
        ;;
esac
