🔖 **td** is a minimal, context-aware todo list manager for the command line, written in Bash.

Unlike standard todo lists, `td` captures the **context** of your task. It records the working directory (or Git root) and optionally a specific file associated with the task. It operates on a stack (LIFO) or queue (FIFO) basis, designed to help developers push tasks onto a stack to clear their mental buffer and pop them off later to resume work.

#### Features

*   **Context Aware**: Automatically records the project root or current directory.
*   **File Linking**: Associates tasks with specific files (e.g., `td main.py "Refactor this"`).
*   **Stack Semantics**: Defaults to LIFO (Last In, First Out) to handle interruptions immediately.
*   **Zero Dependencies**: Relies only on standard tools (`bash`, `date`, `sed`, `grep`).
*   **Clean Interface**: Formatted output with abbreviated paths (e.g., `~/src/project`).

#### Installation

Download the script, make it executable, and move it to your path.

1.  Save the script to a file named `td`.
2.  Make it executable:
    ```bash
    chmod +x td
    ```
3.  Move it to a directory in your `$PATH`:
    ```bash
    sudo mv td /usr/local/bin/
    ```

### Usage

#### Adding Tasks (Push)

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
td l
```

**Output example:**
```text
ID   Date          File            Task
1    01-08 10:15   --              Review PR #42 (~/work/backend)
2    01-08 11:30   server.js       Fix memory leak (~/work/backend)
3    01-08 12:00   styles.css      Adjust padding (~/work/frontend)
```
*Shortcuts: `l`, `list`*

### Completing Tasks (Next / Do)

Retrieves the next task (top of the stack by default). It displays the task details and commands to return to the context.

```bash
td n
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

To delete a specific task by its ID without "doing" it:

```bash
td rm 2
```

### Clearing the List

To remove all tasks:

```bash
td clear
```

## Configuration

On the first run, `td` creates a configuration file at `~/.config/todo/todorc`. You can edit this file to change the default behavior.

```bash
# ~/.config/todo/todorc

# Queue mode: 'lifo' (stack) or 'fifo' (queue)
QUEUE_MODE=lifo

# If true, 'pop'/'next' will only show tasks from the current directory context
PROJECTS_ONLY=false

# If true, 'pop'/'next' will not delete the task from the list automatically
PRESERVE_QUEUE=false
```


