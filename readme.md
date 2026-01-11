![](td.png)

🔖 **td** is a minimal, context-aware todo list manager for the command line, written in Bash.

Unlike standard todo lists, `td` captures the **context** of your task. It records the working directory (or Git root) and optionally a specific file associated with the task. It operates on a stack (LIFO) or queue (FIFO) basis, designed to help developers push tasks onto a stack to clear their mental buffer and pop them off later to resume work.

## Features

*   **Context Aware**: Automatically records the project root or current directory.
*   **File Linking**: Associates tasks with specific files (e.g., `td main.py "Refactor this"`).
*   **Stack Semantics**: Defaults to LIFO (Last In, First Out) to handle interruptions immediately.
*   **Searchable**: Filter tasks by text, filename, or directory path.
*   **Safe**: Built-in Undo command and automatic backups before destructive actions.
*   **History**: Deleted and completed tasks are saved to a history file (`~/.config/td/td.lst.hist`) so you can review and restore past items.
*   **Zero Dependencies**: Relies only on standard tools (`bash`, `date`, `sed`, `grep`).
*   **Clean Interface**: Formatted output with abbreviated paths (e.g., `~/src/project`).

## Installation

```bash
git clone --depth 1 https://github.com/psqlmaster/td.git && \
cd td && sudo cp td /usr/local/bin && sudo chmod +x /usr/local/bin/td && td H
```

## Usage

### Adding Tasks (Push)

You can add a task by simply typing the message.

```bash
td Update nginx config
```

If the first argument is an existing file, `td` links the task to that file.

```bash
td server.js "Fix memory leak in loop"
```
*Shortcuts: `a`, `add`, `push`*

### Listing Tasks (List)

Displays all tasks with their ID, timestamp, linked file, and directory context.

```bash
`td l` or `td` 
```
Show current dir tasks

```bash
`td .` or `td here` 
```
*(Tip: Set `DEFAULT_ACTION=list` in `~/.config/td/tdrc` to list tasks by running `td` without arguments).*

**Output example:**
```text
ID   Date          File            Task
1    01-08 10:15   --              Review PR #42 (~/work/backend)
2    01-08 11:30   server.js       Fix memory leak (~/work/backend)
3    01-08 12:00   styles.css      Adjust padding (~/work/frontend)
```
*Shortcuts: `l`, `list`*

### Searching Tasks

Filter tasks by keyword. `td` performs a case-insensitive search across the task description, filename, and path.

```bash
td s "memory"
```

If you provide a search term, `td` will also search the history of removed/completed tasks and print matches from history in a distinct color under a "History matches:" section. This lets you find previously deleted items without restoring the full list.

**Example (search both current list and history):**

```bash
td s "memory"
```

If there are matches in the history, they will be shown after the regular results.

**Output example:**
```text
ID   Date          File            Task
2    01-08 11:30   server.js       Fix memory leak (~/work/backend)
```
*Shortcuts: `s`, `search`, `find`*

### Completing Tasks (Next / Do)

You can retrieve tasks in two ways: automatically or by ID.

**1. Automatic (Context & Stack)**
Retrieves the top task based on your stack settings (LIFO/FIFO) and current directory.

```bash
td n
```


You can control the display order of the list via the `LIST_ORDER` configuration option (added in recent updates). Valid values are `asc` (oldest first, default) and `desc` (newest first). To set it permanently, edit `~/.config/td/tdrc` and add:

```bash
LIST_ORDER=desc
```

You can also override the option for a single command by prefixing it in the shell:

```bash
LIST_ORDER=desc td l
```
**2. Specific Task**
Retrieves a specific task by its ID (from the `list` command), ignoring the stack order.

```bash
td n 3
```

**Output example:**
```text
>>> NEXT TASK: Fix memory leak
Dir:  cd ~/work/backend
File: server.js
Cmd:  vim server.js
```
*Shortcuts: `n`, `next`, `do`, `pop`*

### Removing Tasks

To delete tasks by ID without "doing" them. You can delete multiple tasks at once.

```bash
td rm 2 4 5
```

### Undo

If you accidentally deleted a task or popped the wrong item, you can revert the last change.

```bash
td u
```
*Shortcuts: `u`, `undo`*

You can also restore a specific history entry by its history ID (HID):

```bash
td u 3
```
This restores the 3rd entry shown by the history command back into the active list.

### Clearing the List

To remove all tasks:

```bash
td clear
```

When you clear the list (or remove/pop tasks), `td` appends the removed lines to the history file. Use the `hist` command to review these entries.

### History

`td` keeps a simple append-only history of removed or completed tasks in `~/.config/td/td.lst.hist`.

- Format: each history row is prefixed with an operation token and timestamp, for example:

	```text
	DEL 167xxxxxxx ~1600000000~/home/user/project~/path/file~Task message~
	```

- Commands:
	- `td h` or `td history` — show removed/completed tasks (colorized and formatted). Note: the help output now lists `H` for the help shortcut and `h` for history.
	- `td u` — undo the last change by restoring the most recent history entry back into the active list (step-wise undo). You can also use `td u <HID>` to restore a specific history ID.

History output is colorized to distinguish it from the active todo list. This makes it easy to scan for previously removed items or to recover work you removed by mistake.

If you would like more advanced history operations (restore a specific history entry, tail N entries, or clear history), those can be added as optional commands later.

## Configuration

On the first run, `td` creates a configuration file at `~/.config/td/tdrc`. You can edit this file to change the default behavior.

```bash
# ~/.config/td/tdrc

# Default action when running 'td' without args: 'help' or 'list'
DEFAULT_ACTION=list

# Queue mode: 'lifo' (stack) or 'fifo' (queue)
QUEUE_MODE=lifo

# If true, 'pop'/'next' will only show tasks from the current directory context
PROJECTS_ONLY=false

# If true, 'pop'/'next' will not delete the task from the list automatically
PRESERVE_QUEUE=false

# Display order for `td l` / `td` when listing tasks. Valid values: 'asc' (oldest first) or 'desc' (newest first).
LIST_ORDER=desc
```
