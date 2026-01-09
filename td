#!/usr/bin/env bash

# td v1.3.0
# Context-aware todo list manager

# handle debugging
if [[ "${TRACE-0}" == "1" ]]; then set -o xtrace; fi

# Vars
CONFIG_DIR="${XDG_CONFIG_HOME:=${HOME}/.config}/td"
CONFIG_FILE="tdrc"
TODO_LIST="${CONFIG_DIR}/td.lst"
HIST_FILE="${CONFIG_DIR}/td.lst.hist"

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

function show_help {
    echo -e "${BLUE}Usage: td [cmd] [args]${NC}"
    echo -e "  a, push [f] MSG   Add task"
    echo -e "  l, list           List tasks"
    echo -e "  s, search STR     Search tasks"
    echo -e "  n, next [N]       Pop/Finish next task"
    echo -e "  rm <N> [N...]     Remove task ID(s)"
    echo -e "  u, undo           Undo last change"
    echo -e "  c, clear          Clear all"
    echo -e "  h, help           Show help"
    echo -e "  hst, history     Show removed tasks history"
}

function config_if_needed {
    if [[ ! -d ${CONFIG_DIR} ]]; then mkdir -p "${CONFIG_DIR}"; fi
    if [[ ! -s ${CONFIG_DIR}/${CONFIG_FILE} ]]; then
        { echo "DEFAULT_ACTION=${DEFAULT_ACTION}"; echo "PRESERVE_QUEUE=${PRESERVE_QUEUE}";
          echo "PROJECTS_ONLY=${PROJECTS_ONLY}"; echo "QUEUE_MODE=${QUEUE_MODE}"; } > "${CONFIG_DIR}/${CONFIG_FILE}"
    fi
    source "${CONFIG_DIR}/${CONFIG_FILE}"
}

function create_backup {
    # keep compatibility: ensure config directory exists
    if [[ ! -d ${CONFIG_DIR} ]]; then mkdir -p "${CONFIG_DIR}"; fi
}

function append_history {
    # Store removed line(s) in history with an operation timestamp.
    # Format: DEL <op_ts> <raw_line>
    local raw_line="$1"
    if [[ -z "${raw_line}" ]]; then return; fi
    if [[ ! -d ${CONFIG_DIR} ]]; then mkdir -p "${CONFIG_DIR}"; fi
    echo "DEL $(date +%s) ${raw_line}" >> "${HIST_FILE}"
}

function undo_last_change {
    # Try step-wise undo from history first
    if [[ -s "${HIST_FILE}" ]]; then
        local last_entry
        last_entry=$(tail -n 1 "${HIST_FILE}")
        # remove last history line
        if [[ $(uname -s) == "Darwin" ]]; then
            sed -i '' -e '$d' "${HIST_FILE}"
        else
            sed -i '$d' "${HIST_FILE}"
        fi

        # extract raw_line (history format: DEL <op_ts> <raw_line>)
        local raw_line
        raw_line=$(echo "${last_entry}" | cut -d' ' -f3-)

        # restore the raw line to TODO_LIST and re-sort by internal timestamp
        echo "${raw_line}" >> "${TODO_LIST}"
        # reorder by the internal timestamp (field 2 between tildes)
        awk -F'~' '{print $2 "\t" $0}' "${TODO_LIST}" | sort -n | cut -f2- > "${TODO_LIST}.tmp" && mv "${TODO_LIST}.tmp" "${TODO_LIST}"

        echo -e "${BLUE}Undone:${NC} Restored last change from history."
        show_todos
        return
    fi

    # No history available
    echo -e "${RED}Error: Nothing to undo (history is empty).${NC}"
    return
}

function push_to_stack {
    create_backup

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
    local search_term="$1"
    
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
        
        if [[ -n "${search_term}" ]]; then
            local context_str="${WHAT} ${FILE} ${WHERE}"
            if ! echo "${context_str}" | grep -q -i -- "${search_term}"; then
                ((counter++))
                continue
            fi
        fi
        
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

function show_history {
    local search_term="$1"

    if [[ ! -s "${HIST_FILE}" ]]; then
        echo -e "${GRAY}No history.${NC}"; return
    fi

    printf "${CYAN}%-3s %-12s %-15s %s${NC}
" "HID" "Date" "File" "Task"

    local counter=1
    while read -r LINE; do
        # history format: DEL <op_ts> <raw_line>
        OP=$(echo "${LINE}" | cut -d' ' -f1)
        OPTS=$(echo "${LINE}" | cut -d' ' -f2)
        RAW_LINE=$(echo "${LINE}" | cut -d' ' -f3-)

        # extract fields from raw_line which is ~ts~where~file~what~
        _WHEN=$(echo "${RAW_LINE}" | cut -d~ -f2)
        WHERE=$(echo "${RAW_LINE}" | cut -d~ -f3)
        FILE=$(echo "${RAW_LINE}" | cut -d~ -f4)
        WHAT=$(echo "${RAW_LINE}" | cut -d~ -f5)

        DISPLAY_WHERE="${WHERE/#$HOME/\~}"
        if [[ -n "${FILE}" ]]; then
            DISPLAY_FILE="${YELLOW}${FILE}${NC}"
        else
            DISPLAY_FILE="${GRAY}--${NC}"
        fi

        if [[ -n "${search_term}" ]]; then
            local context_str="${WHAT} ${FILE} ${WHERE}"
            if ! echo "${context_str}" | grep -q -i -- "${search_term}"; then
                ((counter++))
                continue
            fi
        fi

        find_when "${_WHEN}"

        # print history line in cyan
        printf "${CYAN}%-3s${NC} %-12s %-15b %s ${CYAN}(%s)${NC}\n" \
            "${counter}" "${WHEN}" "${DISPLAY_FILE}" "${WHAT}" "${DISPLAY_WHERE}"

        ((counter++))
    done < "${HIST_FILE}"
}

function delete_todo {
    if [[ $# -eq 0 ]]; then
        echo -e "${RED}Error: Use number(s) (e.g., td rm 2 3)${NC}"
        exit 1
    fi

    for id in "$@"; do
        if ! [[ "$id" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Error: '$id' is not a number.${NC}"
            exit 1
        fi
    done

    create_backup

    local sorted_ids
    sorted_ids=$(printf "%s\n" "$@" | sort -rn | uniq)

    for id in $sorted_ids; do
        local total
        total=$(wc -l < "${TODO_LIST}")

        if (( id > total )) || (( id < 1 )); then
            echo -e "${RED}Error: Task $id not found (skipped).${NC}"
            continue
        fi

        local line_content
        line_content=$(sed "${id}q;d" "${TODO_LIST}")
        local what=$(echo "${line_content}" | cut -d~ -f5)

        # save deleted line to history for step-wise undo
        append_history "${line_content}"

        if [[ $(uname -s) == "Darwin" ]]; then
            sed -i '' "${id}d" "${TODO_LIST}"
        else
            sed -i "${id}d" "${TODO_LIST}"
        fi

        echo -e "${RED}Deleted ($id):${NC} $what"
    done
}

function pop_from_stack {
    local requested_id="$1"
    local LINE=""
    
    TODOS=$(wc -l "${TODO_LIST}" 2>/dev/null | cut -d' ' -f1)
    if [[ ${TODOS} -lt 1 ]]; then echo -e "${BLUE}Done!${NC}"; exit 0; fi

    if [[ -n "$requested_id" ]]; then
        if ! [[ "$requested_id" =~ ^[0-9]+$ ]]; then
             echo -e "${RED}Error: ID must be a number.${NC}"; exit 1
        fi
        if (( requested_id > TODOS )) || (( requested_id < 1 )); then
             echo -e "${RED}Error: Task $requested_id not found.${NC}"; exit 1
        fi
        LINE=$(sed "${requested_id}q;d" "${TODO_LIST}")
    else
        _toplevel=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
        [[ "${QUEUE_MODE}" == "lifo" ]] && CMD="tail" || CMD="head"

        LINE=$(grep "~${_toplevel}~" "${TODO_LIST}" | $CMD -n 1)
        if [[ "${PROJECTS_ONLY}" == 'false' ]] && [[ -z "${LINE}" ]]; then
            LINE=$($CMD -n 1 "${TODO_LIST}")
        fi
    fi

    if [[ -z "${LINE}" ]]; then echo -e "${BLUE}No context todos.${NC}"; exit 0; fi

    RAW_TS=$(echo "${LINE}" | cut -d~ -f2)
    WHERE=$(echo "${LINE}" | cut -d~ -f3)
    FILE=$(echo "${LINE}" | cut -d~ -f4)
    WHAT=$(echo "${LINE}" | cut -d~ -f5)

    DISPLAY_WHERE="${WHERE/#$HOME/\~}"

    echo -e "${GREEN}>>> NEXT TASK:${NC} ${WHAT}"
    [[ "${WHERE}" != "${PWD}" ]] && echo -e "${GRAY}Dir:${NC}  cd ${DISPLAY_WHERE}" || echo -e "${GRAY}Dir:${NC}  (Current)"
    
    if [[ -n "${FILE}" ]]; then
        echo -e "${GRAY}File:${NC} ${YELLOW}${FILE}${NC}"
        [[ -n "${EDITOR}" ]] && echo -e "${GRAY}Cmd:${NC}  ${EDITOR} ${FILE}"
    fi

    if [[ "${PRESERVE_QUEUE}" == 'false' ]]; then
        create_backup
        # normalize LINE (strip possible leading line-number from grep -n)
        local raw_line
        raw_line="${LINE}"
        if echo "${raw_line}" | grep -qE '^[0-9]+:'; then
            raw_line=$(echo "${raw_line}" | sed 's/^[0-9]\+://')
        fi

        # save to history before removing
        append_history "${raw_line}"

        if [[ $(uname -s) == "Darwin" ]]; then
            sed -i '' "/^~${RAW_TS}~/d" "${TODO_LIST}"
        else
            sed -i "/^~${RAW_TS}~/d" "${TODO_LIST}"
        fi
    fi
}

# --- Main Logic ---

config_if_needed

if [[ $# -eq 0 ]]; then
    case "${DEFAULT_ACTION}" in
        list) show_todos ;;
        help|*) show_help ;;
    esac
    exit 0
fi

CMD=$1
shift

case "$CMD" in
    l|list|ls)
        show_todos
        ;;
    s|search|find|grep)
        # search current todos
        show_todos "$*"
        # if search term provided, also search history and show matches
        if [[ -n "$*" ]]; then
            echo
            echo -e "${CYAN}History matches:${NC}"
            show_history "$*"
        fi
        ;;
    n|next|do|pop|pp)
        pop_from_stack "$1"
        ;;
    rm|del|delete)
        delete_todo "$@"
        ;;
    u|undo)
        undo_last_change
        ;;
    c|clear)
        create_backup
        # save all current lines to history
        if [[ -s "${TODO_LIST}" ]]; then
            while read -r _line; do
                append_history "${_line}"
            done < "${TODO_LIST}"
        fi
        > "${TODO_LIST}"
        echo -e "${BLUE}Cleared.${NC}"
        ;;
    a|add|p|push)
        push_to_stack "$@"
        ;;
    h|help|--help)
        show_help
        exit 0
        ;;
    hst|history)
        show_history
        exit 0
        ;;
    *)
        if [[ -n "$CMD" ]]; then
             push_to_stack "$CMD" "$@"
             exit 0
        fi
        show_help
        exit 1
        ;;
esac

