#!/usr/bin/env bash

# td v1.6.4
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
DEFAULT_ACTION=list
PRESERVE_QUEUE=false
PROJECTS_ONLY=false
QUEUE_MODE=lifo
LIST_ORDER=desc

function show_help {
    echo -e "Minimal, context-aware todo list manager v1.6.4"
    echo -e "Copyright (c) 2026, Alexander Shcheglov @sqlmaster"
    echo -e "${BLUE}Usage: td [cmd] [args]${NC}"
    echo -e "  a|push [f] MSG       Add task"
    echo -e "  l|list or nothing    List tasks"
    echo -e "  .|here [n|N]         Show or Next/Pop task in current dir"
    echo -e "  s|search STR         Search tasks"
    echo -e "  n|next [N]           Pop/Finish next task"
    echo -e "  rm <N> [N...]        Remove task ID(s)"
    echo -e "  u|undo [HID]         Undo last change or restore specific history ID"
    echo -e "  c|clear              Clear all (move to history)"
    echo -e "  rmh <HID> [HID...]   Remove history ID(s)"
    echo -e "  ch|clearh            Clear history (permanent delete)"
    echo -e "  b|bak                Backup config to current dir"
    echo -e "  H|help               Show help"
    echo -e "  h|history            Show removed tasks history"
    echo -e ""
    echo -e "Config file: ${CYAN}cat ${CONFIG_DIR}/${CONFIG_FILE}${NC}"
    echo -e "  Shows current configuration and available options:"
    echo -e "    - LIST_ORDER=asc|desc        Display order for \`td\` list"
    echo -e "    - QUEUE_MODE=lifo|fifo       How next task is selected"
    echo -e "    - PRESERVE_QUEUE=true|false  Keep tasks when popping"
    echo -e "    - PROJECTS_ONLY=true|false   Prefer project-scoped tasks"
    echo -e "    - DEFAULT_ACTION=list|help   Default command when running \`td\` without args"
}

function config_if_needed {
    if [[ ! -d ${CONFIG_DIR} ]]; then mkdir -p "${CONFIG_DIR}"; fi
    if [[ ! -s ${CONFIG_DIR}/${CONFIG_FILE} ]]; then
                { echo "DEFAULT_ACTION=${DEFAULT_ACTION}"; echo "PRESERVE_QUEUE=${PRESERVE_QUEUE}";
                    echo "PROJECTS_ONLY=${PROJECTS_ONLY}"; echo "QUEUE_MODE=${QUEUE_MODE}"; echo "LIST_ORDER=${LIST_ORDER}"; } > "${CONFIG_DIR}/${CONFIG_FILE}"
    fi

    # Source config to apply config values over defaults.
    # Then re-apply exported environment variables so env takes precedence: env > config > defaults.
    source "${CONFIG_DIR}/${CONFIG_FILE}"

    for v in DEFAULT_ACTION PRESERVE_QUEUE PROJECTS_ONLY QUEUE_MODE LIST_ORDER; do
        if printenv "${v}" >/dev/null 2>&1; then
            val=$(printenv "${v}")
            printf -v "${v}" '%s' "${val}"
        fi
    done
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
    local hid="$1"

    if [[ ! -s "${HIST_FILE}" ]]; then
        echo -e "${RED}Error: Nothing to undo (history is empty).${NC}"
        return
    fi

    # If a history id is provided, restore that specific entry, otherwise restore last
    local entry_line
    if [[ -n "${hid}" ]]; then
        if ! [[ "${hid}" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Error: History ID must be a number.${NC}"
            return 1
        fi

        local total
        total=$(wc -l < "${HIST_FILE}")
        if (( hid < 1 )) || (( hid > total )); then
            echo -e "${RED}Error: History ID ${hid} not found.${NC}"
            return 1
        fi

        # extract the requested history line
        entry_line=$(sed "${hid}q;d" "${HIST_FILE}")

        # remove that specific history line
        if [[ $(uname -s) == "Darwin" ]]; then
            sed -i '' -e "${hid}d" "${HIST_FILE}"
        else
            sed -i "${hid}d" "${HIST_FILE}"
        fi
    else
        # default: take last history entry
        entry_line=$(tail -n 1 "${HIST_FILE}")
        # remove last history line
        if [[ $(uname -s) == "Darwin" ]]; then
            sed -i '' -e '$d' "${HIST_FILE}"
        else
            sed -i '$d' "${HIST_FILE}"
        fi
    fi

    # extract raw_line (history format: DEL <op_ts> <raw_line>)
    local raw_line
    raw_line=$(echo "${entry_line}" | cut -d' ' -f3-)

    # restore the raw line to TODO_LIST and re-sort by internal timestamp
    echo "${raw_line}" >> "${TODO_LIST}"
    # reorder by the internal timestamp (field 2 between tildes)
    awk -F'~' '{print $2 "\t" $0}' "${TODO_LIST}" | sort -n | cut -f2- > "${TODO_LIST}.tmp" && mv "${TODO_LIST}.tmp" "${TODO_LIST}"

    if [[ -n "${hid}" ]]; then
        echo -e "${BLUE}Undone:${NC} Restored history ID ${hid}."
    else
        echo -e "${BLUE}Undone:${NC} Restored last change from history."
    fi
    show_todos
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

    _toplevel="${PWD}" 
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

function print_todo_line {
    # print_todo_line <ID> <LINE> [search_term]
    local id="$1"
    local LINE="$2"
    local search_term="$3"
    local _WHEN WHERE FILE WHAT
    WHERE=$(echo "${LINE}" | cut -d~ -f3)

    if [[ -n "${TD_ONLY_CONTEXT}" ]]; then
        if [[ "${WHERE}" != "${TD_ONLY_CONTEXT}" ]]; then
            return 1
        fi
    fi

    local _WHEN WHERE FILE WHAT
    _WHEN=$(echo "${LINE}" | cut -d~ -f2)
    WHERE=$(echo "${LINE}" | cut -d~ -f3)
    FILE=$(echo "${LINE}" | cut -d~ -f4)
    WHAT=$(echo "${LINE}" | cut -d~ -f5)

    if [[ -n "${search_term}" ]]; then
        local context_str="${WHAT} ${FILE} ${WHERE}"
        if ! echo "${context_str}" | grep -q -i -- "${search_term}"; then
            return 1
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
        "${id}" "${WHEN}" "${DISPLAY_FILE}" "${WHAT}" "${DISPLAY_WHERE}"

    return 0
}

function show_todos {
    local search_term="$1"
    
    if [[ ! -s "${TODO_LIST}" ]]; then
        echo -e "${GRAY}Empty.${NC}"; return
    fi
    printf "${GRAY}%-3s %-12s %-15s %s${NC}\n" "ID" "Date" "File" "Task"

    local counter=1
    local order="${LIST_ORDER:-asc}"
    # normalize: remove CR, lowercase
    order="${order//$'\r'/}"
    order="${order,,}"

    if [[ "${order}" == "desc" ]]; then
        mapfile -t LINES < <(awk '{lines[NR] = $0} END {for (i=NR;i>=1;i--) print lines[i]}' "${TODO_LIST}")
        for LINE in "${LINES[@]}"; do
            if print_todo_line "${counter}" "${LINE}" "${search_term}"; then
                ((counter++))
            fi
        done
    else
        while read -r LINE; do
            if print_todo_line "${counter}" "${LINE}" "${search_term}"; then
                ((counter++))
            fi
        done < "${TODO_LIST}"
    fi
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

function delete_history {
    if [[ $# -eq 0 ]]; then
        echo -e "${RED}Error: Use history ID(s) (e.g., td rmh 2 3)${NC}"
        exit 1
    fi

    for id in "$@"; do
        if ! [[ "$id" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Error: '$id' is not a number.${NC}"
            exit 1
        fi
    done

    local sorted_ids
    sorted_ids=$(printf "%s\n" "$@" | sort -rn | uniq)

    for id in $sorted_ids; do
        local total
        total=$(wc -l < "${HIST_FILE}")

        if (( id > total )) || (( id < 1 )); then
            echo -e "${RED}Error: History $id not found (skipped).${NC}"
            continue
        fi

        local line_content
        line_content=$(sed "${id}q;d" "${HIST_FILE}")
        local raw_line
        raw_line=$(echo "${line_content}" | cut -d' ' -f3-)
        local what
        what=$(echo "${raw_line}" | cut -d~ -f5)

        if [[ $(uname -s) == "Darwin" ]]; then
            sed -i '' "${id}d" "${HIST_FILE}"
        else
            sed -i "${id}d" "${HIST_FILE}"
        fi

        echo -e "${RED}Deleted history ($id):${NC} $what"
    done
}

function clear_history {
    > "${HIST_FILE}"
    echo -e "${BLUE}History cleared.${NC}"
}

function delete_todo {
    if [[ $# -eq 0 ]]; then
        echo -e "${RED}Error: Use number(s) (e.g., td rm 2 3)${NC}"
        exit 1
    fi

    local total
    total=$(wc -l < "${TODO_LIST}")

    # Determine current display order from config
    local order="${LIST_ORDER:-asc}"
    order="${order//$'\r'/}"
    order="${order,,}"

    local real_ids=()
    for id in "$@"; do
        # Validate that the input is a number
        if ! [[ "$id" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Error: '$id' is not a number.${NC}"
            exit 1
        fi
        
        # Check if ID is within existing range
        if (( id > total )) || (( id < 1 )); then
            echo -e "${RED}Error: Task $id not found (skipped).${NC}"
            continue
        fi

        # Map visual ID to the actual physical line number in the file
        # If order is descending (newest on top), Visual ID 1 is the last line in the file
        # Formula: Real_Line = Total_Lines - Visual_ID + 1
        if [[ "${order}" == "desc" ]]; then
            real_ids+=($(( total - id + 1 )))
        else
            real_ids+=($id)
        fi
    done

    # Sort real line numbers in descending order before deleting
    # This is crucial: deleting line 10 first ensures line 2 stays at index 2
    local sorted_real_ids
    sorted_real_ids=$(printf "%s\n" "${real_ids[@]}" | sort -rn | uniq)

    for rid in $sorted_real_ids; do
        local line_content
        line_content=$(sed "${rid}q;d" "${TODO_LIST}")
        local what=$(echo "${line_content}" | cut -d~ -f5)

        # Archive the task to history before permanent removal
        append_history "${line_content}"

        # Delete the specific line from the file
        if [[ $(uname -s) == "Darwin" ]]; then
            sed -i '' "${rid}d" "${TODO_LIST}"
        else
            sed -i "${rid}d" "${TODO_LIST}"
        fi

        echo -e "${RED}Deleted:${NC} $what"
    done
}

function pop_from_stack {
    local requested_id="$1"
    local LINE=""
    
    # Получаем общее количество задач
    local total_todos
    total_todos=$(wc -l < "${TODO_LIST}" 2>/dev/null || echo 0)
    
    if [[ ${total_todos} -lt 1 ]]; then echo -e "${BLUE}Done!${NC}"; exit 0; fi

    if [[ -n "$requested_id" ]]; then
        if ! [[ "$requested_id" =~ ^[0-9]+$ ]]; then
             echo -e "${RED}Error: ID must be a number.${NC}"; exit 1
        fi
        if (( requested_id > total_todos )) || (( requested_id < 1 )); then
             echo -e "${RED}Error: Task $requested_id not found.${NC}"; exit 1
        fi

        # Исправление: Маппинг визуального ID на физическую строку файла
        local order="${LIST_ORDER:-asc}"
        order="${order//$'\r'/}"
        order="${order,,}"
        
        local real_id
        if [[ "${order}" == "desc" ]]; then
            # Если порядок обратный, ID 1 — это последняя строка (total_todos)
            real_id=$(( total_todos - requested_id + 1 ))
        else
            real_id=$requested_id
        fi
        
        LINE=$(sed "${real_id}q;d" "${TODO_LIST}")
    else
        # Логика для td n без аргументов (следующая задача по очереди)
        [[ "${QUEUE_MODE}" == "lifo" ]] && CMD="tail" || CMD="head"

        if [[ "${PROJECTS_ONLY}" == 'true' ]]; then
            _toplevel="${PWD}"
            LINE=$(grep "~${_toplevel}~" "${TODO_LIST}" | $CMD -n 1)
        else
            LINE=$($CMD -n 1 "${TODO_LIST}")
        fi
    fi

    if [[ -z "${LINE}" ]]; then echo -e "${BLUE}No context todos.${NC}"; exit 0; fi

    # Далее идет старый код обработки переменной LINE...
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
        local raw_line="${LINE}"
        if echo "${raw_line}" | grep -qE '^[0-9]+:'; then
            raw_line=$(echo "${raw_line}" | sed 's/^[0-9]\+://')
        fi
        append_history "${raw_line}"

        if [[ $(uname -s) == "Darwin" ]]; then
            sed -i '' "/~${RAW_TS}~/d" "${TODO_LIST}"
        else
            sed -i "/~${RAW_TS}~/d" "${TODO_LIST}"
        fi
    fi
}

function backup_data {
    # Check if config directory exists
    if [[ ! -d "${CONFIG_DIR}" ]]; then
        echo -e "${RED}Error: Config directory ${CONFIG_DIR} does not exist.${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Source:${NC} ${CONFIG_DIR}"
    echo -e "${YELLOW}Dest:${NC}   ${PWD}"
    
    # Ask for user confirmation
    read -p "Create backup of all config data to current directory? [y/N] " -n 1 -r
    echo "" # move to new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GRAY}Backup aborted.${NC}"
        return
    fi

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local archive_name="td_backup_${timestamp}.tar.gz"

    # Create tar archive
    # -C changes to CONFIG_DIR so the archive doesn't contain full absolute paths
    if tar -czf "${archive_name}" -C "${CONFIG_DIR}" .; then
        echo -e "${GREEN}Success:${NC} Backup saved to ${BLUE}${archive_name}${NC}"
    else
        echo -e "${RED}Error: Failed to create backup archive.${NC}"
        exit 1
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
    rmh|delh|rmhist)
        delete_history "$@"
        ;;
    u|undo)
        undo_last_change
        ;;
    b|bak|backup)
        backup_data
        ;;
    here|.)
        # Determine current context (directory)
        CURRENT_CTX="${PWD}" 

        # Check for arguments
        if [[ $# -gt 0 ]]; then
            ARG="$1"
            TARGET_IDX=""

            # Check: is this a 'next task' command or a specific number?
            case "$ARG" in
                n|next|do|pop|pp)
                    # If "next" command, target the 1st task in the visible list
                    TARGET_IDX=1
                    ;;
                *)
                    # If it's a number, use it directly
                    if [[ "$ARG" =~ ^[0-9]+$ ]]; then
                        TARGET_IDX="$ARG"
                    else
                        echo -e "${RED}Error: Invalid argument '$ARG'. Use a number or 'n/next'.${NC}"
                        exit 1
                    fi
                    ;;
            esac

            # FIX: Removed 'local' keyword because we are in global scope
            _sort_order="${LIST_ORDER:-asc}"
            _sort_order="${_sort_order//$'\r'/}"
            _sort_order="${_sort_order,,}"

            # AWK finds the real ID of the task positioned at TARGET_IDX within the current context
            REAL_ID=$(awk -v ctx="$CURRENT_CTX" -v idx="$TARGET_IDX" -v ord="$_sort_order" -F"~" '
            BEGIN { count=0 }
            {
                # $3 is path (context). Format: ~ts~path~file~task~
                if ($3 == ctx) {
                    count++
                    matches[count] = NR
                }
            }
            END {
                if (count == 0) exit 1
                
                # With desc sort (newest on top), the 1st list element is the last matched line in file
                if (ord == "desc") {
                    target_pos = count - idx + 1
                } else {
                    target_pos = idx
                }

                # If position is valid, print the line number (Global ID)
                if (target_pos > 0 && target_pos <= count) {
                    print matches[target_pos]
                } else {
                    exit 1
                }
            }' "${TODO_LIST}")

            # Handle search result
            if [[ -z "$REAL_ID" ]]; then
                if [[ "$TARGET_IDX" == "1" ]]; then
                    echo -e "${BLUE}No context todos.${NC}"
                    exit 0
                else
                    echo -e "${RED}Error: Task #$TARGET_IDX not found in current directory.${NC}"
                    exit 1
                fi
            fi

            # Execute/Pop task by real ID
            pop_from_stack "$REAL_ID"

        else
            # No arguments — just show the list filtered by context
            TD_ONLY_CONTEXT="$CURRENT_CTX" show_todos
        fi
        ;;   
    c|clear)
        # save all current lines to history
        if [[ -s "${TODO_LIST}" ]]; then
            while read -r _line; do
                append_history "${_line}"
            done < "${TODO_LIST}"
        fi
        > "${TODO_LIST}"
        echo -e "${BLUE}Cleared.${NC}"
        ;;

    ch|clearch|clearh)
        clear_history
        ;;
    a|add|p|push)
        push_to_stack "$@"
        ;;
    H|help|--help)
        show_help
        exit 0
        ;;
    h|history)
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
