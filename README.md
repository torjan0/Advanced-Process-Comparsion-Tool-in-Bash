
# Advanced Process Comparison Tool

Advanced Process Comparison Tool is a Bash script that analyzes your system’s running processes using the `/proc` filesystem. It extracts detailed information—such as the command, memory usage, CPU ticks, state, nice value, start time, and process owner—and then compares processes based on a combined difference metric (memory difference plus CPU ticks difference). This tool is packed with features including advanced filtering, sorting, multiple output formats, interactive mode, auto-refresh monitoring, parallel scanning, and summary statistics.

---

## Features

- **Process Analysis:** Reads and parses process details from `/proc`.
- **Advanced Filtering:**  
  Filter processes by:
  - Minimum/maximum memory usage
  - Minimum CPU ticks
  - Command substring
  - Owner (user or UID)
    
- **Custom Sorting:**  
  Sort matching processes by any field:
  - `pid`, `cmd`, `mem`, `cpu`, `state`, `nice`, `start`, or `user`
  in ascending or descending order.

- **Multiple Output Formats:**  
  Choose from:
  - Plain text (with optional color)
  - JSON
  - CSV
  - HTML
    
- **Interactive Mode:**  
  Manually select which two processes to compare from a numbered list.
  
- **Monitoring Mode:**  
  Auto-refresh the report every _n_ seconds with optional desktop notifications when the best pair changes.
  
- **Parallel Scanning:**  
  Use GNU parallel to speed up process scanning (if installed).
  
- **Summary Statistics:**  
  View total matching processes, average memory usage, and average CPU ticks.
  
- **Portable and Self-Contained:**  
  Written entirely in Bash using standard Linux utilities.

---

## Requirements

- **Bash:** Version 4 or later.
- **Linux:** With the `/proc` filesystem available.
- **GNU getopt:** For enhanced option parsing.
- _Optional:_  
  - **GNU parallel:** For faster scanning.
  - **notify-send:** For desktop notifications.

---

## Installation

Clone the repository and make the script executable:

```bash
git clone https://github.com/your_username/ProcessCompareBash.git
cd ProcessCompareBash
chmod +x process_compare.sh
```

### Usage

Run the script with your desired options. For help, run:

```bash
./process_compare.sh -h
```

### Command-Line Options

#### Memory & CPU Filters:

- `-m, --min-memory <kB>`: Minimum memory usage (in kB) for filtering (default: 0)
- `-M, --max-memory <kB>`: Maximum memory usage for filtering (default: no limit)
- `-C, --min-cpu <ticks>`: Minimum CPU ticks for filtering (default: 0)

#### Command & User Filters:

- `-c, --cmd-filter <string>`: Filter processes by command substring (default: match all)
- `-u, --user <username/UID>`: Filter processes by owner (username or UID)

#### Sorting:

- `-s, --sort <field>`: Sort by a field: pid, cmd, mem, cpu, state, nice, start, or user (default: pid)
- `-O, --order <asc|desc>`: Sort order (default: asc)

#### Output Format:

- `-o, --output-format <fmt>`: Output format: text (default), json, csv, or html
- `--csv`: Alias for CSV output
- `--html`: Alias for HTML output

#### Modes & Additional Options:

- `-I, --interactive`: Enable interactive mode to manually select a process pair
- `-r, --refresh <seconds>`: Auto-refresh interval (in seconds) for monitoring mode (default: off)
- `-p, --parallel`: Use GNU parallel for faster scanning
- `-a, --all`: List all matching processes in addition to the best pair
- `-S, --summary`: Display summary statistics (total count, average memory/CPU)
- `-A, --alert`: Enable desktop notifications (using notify-send) when the best pair changes
- `-l, --log-file <filename>`: Log debug messages to a specified file
- `-v, --verbose`: Enable verbose (debug) logging
- `-f, --file <output_file>`: Write output to a specified file
- `-h, --help`: Display this help message

---

## How It Works

The script works by scanning the `/proc` directory for numeric subdirectories (each representing a process). It extracts critical information such as CPU time, memory, and user ID, applies filters, sorts the results, and compares the best matches.

---

## Examples

### Example 1: Basic Usage (Plain Text Output)

```bash
./process_compare.sh --min-memory 0 --cmd-filter bash
```

### Example 2: JSON Output

```bash
./process_compare.sh --min-memory 0 --cmd-filter bash --output-format json
```

### Example 3: CSV Output

```bash
./process_compare.sh -m 0 -c bash --output-format csv
```

### Example 4: HTML Output

```bash
./process_compare.sh -m 0 -c bash --output-format html
```

---

## Contributing

Contributions, bug fixes, and feature enhancements are very welcome! Please open an issue or submit a pull request if you have ideas for improvements or encounter any problems.

---

## License

This project is licensed under the MIT License.

---

## Final Notes

Advanced Process Comparison Tool is designed to provide deep insights into your system’s processes with a rich set of features. Whether you prefer plain text output for quick checks or need structured data in JSON, CSV, or HTML for further analysis, this tool is flexible enough to meet your needs.

Enjoy using it, and please share your feedback!
