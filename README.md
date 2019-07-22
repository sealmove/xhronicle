# xhronicle: a xonsh history frontend (WIP)

## What is xonsh?
Xonsh is a relatively new shell (2016) and it's amazing in many ways. First and
foremost it's an innovative shell language which combines the power of traditional
shell language and the beauty of python. This project focuses on another cool
feature though, the history system.

## Xonsh history backend
Xonsh's history system is plugable. There are already currently 3 available
choices after installing (json, sqlite, dummy) and you can also write your own
backend! This project uses the default backend (json), although it can be extended to support more.

Xonsh logs commands *per session* in json files with a unique session id.
Each session file includes roughly this information:
- enviroment
- session timestamps (start, end)
- list of commands
	- command
	- timestamps (start, end)
	- return code
	- output (stdout)

## What is lacking?
As you can imagine, xonsh's history system is increadibly powerful! It even
provides a command, `history replay`, which can replay a session (kinda like
asciinema and the likes). Sadly this is the only frontend feature that makes
full use of the information in the json files. If you want to see any information
about a specific command, all you can do is search the json files manually or
replay the session.
**tl;dr: Xonsh lacks a frontend tool for searching through the
json files or producing traditional history log files**.

## What exactly does xhronicle do?
Xhronicle is a simple cli with the following 3 subcommands:
- print [-u] [-i] [-r] [-t] [-s] [since] [until]
- output \<session id\> \<command id\> [--stripcolors]
- enviroment \<session id\> [--json]

You don't have to type the whole subcommand. For example `xhronicle p`,
`xhronicle pri` and `xhronicle print` are all equivelant.

### `print`:
Prints a log file. If no option is provided, then only the
commands are printed **in precise chronological order**, one line each.
With options you can print more information in the line.
None of the options take arguments and they are **order-sensitive**!

| Short | Long | Meaning |
|-------|------|----------
| -u | --user | user who ran the command |
| -i | --id | session id and command is |
| -r | --returncode | return code of the command |
| -s | --start | date and time when the command started execution |
| -f | --finish | date and time when the command finished execution |
| -d | --duration | duration of command execution in seconds |
| -n | --nocolor | strips the output free of ascii color escape sequences |

### `output`
Takes 2 mandatory arguments, a session id and a command id (collectively they map
to a unique command), and writes to stdout what was written to stdout and stderr
(by the command) when it was executed.

### `enviroment`
Take 1 argument, a session id, and prints the *initial* enviroment variables of the corresponding session.

## How to generate binary
* Clone
* [Install Nim](https://nim-lang.org/install.html)
* Compile (`nim c -d:release -o:xhronicle xhronicle.nim`) 

- a simple configuration file is needed to specify the following:
	- Users' names and corresponding paths to the xonsh history directory
	- Colors
	- Timedate format
	- Duration format

## Notes
Not every feature described above is implemented. The project is currently
incomplete. More features will be added too.