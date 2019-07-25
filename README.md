# xhronicle: a xonsh history frontend

## What is xonsh?
Xonsh is a relatively new shell (2016) and it's amazing in many ways. First and
foremost it's an innovative shell language which combines the power of
traditional shell language and the beauty of python. This project focuses on
another cool feature though, the history system.

## Xonsh history backend
Xonsh's history system is plugable. There are already currently 3 available
choices after installing (json, sqlite, dummy) and you can also write your own
backend! This project uses the default backend (json), although it can be
extended to support more.

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
full use of the information in the json files. If you want to see any
information about a specific command, all you can do is search the json files
manually or replay the session.
**tl;dr: Xonsh lacks a frontend tool for searching through the
json files or producing traditional history log files**.

## What exactly does xhronicle do?
Xhronicle is a simple cli with the following subcommands:
- print [-u] [-i] [-r] [-b] [-e] [-d] [-f \<date/time\>] [-t \<date/time\>] [-s \<session id\>] 
- output \<session id\> \<command index\> [--nocolor]
- enviroment \<session id\> [--minify]
- timestamps \<session id\>

You don't have to type the whole subcommand. For example `xhronicle p`,
`xhronicle pri` and `xhronicle print` are all equivelant.

## `print`
Prints a log file. If no option is provided, then only the
commands are printed **in precise chronological order**, one line each.
With options you can print more information in the line or filter commands.
It takes no arguments.

### information
None of these options take arguments and they are **order-sensitive**!

| Short | Long | Meaning |
|-------|------|----------
| -u | --user | user who ran the command
| -i | --id | session id and command is
| -r | --returncode | return code of the command
| -b | --begin | date and time when the command beginned execution
| -e | --end | date and time when the command ended execution
| -d | --duration | duration of command execution in seconds

The date and time are formated according to the config file (see [below](https://github.com/sealmove/xhronicle#configuration)).
If no config file is provided, then `dd MMM YYYY hh:mm:ss` is used.

### filtering
All filtering commands require arguments.

| Short | Long | Argument(s) | Meaning
|-------|------|---------- | -
| -f | --from | date/time | only show commands ran after [date/time]
| -t | --till | date/time | only show command
| -s | --session | session id | only show commands ran during [session]

date/time for `--from` and `--till` options must be formatted according to the
config file. If no config file is provided, then `yyyy-M-d-h:m:s` is used.
There is a plan for making this more flexible in the future so that it accepts
a multitude of formats by default.

There is also an option to strip colors. It accepts no arguments:

| Short | Long | Meaning
|-------|------|----------
| -n | --nocolor | strips the output free of ascii color escape sequences

## `output`
Takes 3 mandatory arguments: user, session id, command index (collectively they
map to a unique command); and writes to stdout what was written to stdout and
stderr (by the command) when it was executed.

There is one option available which accepts no arguments:

| Short | Long | Meaning
|-------|------|----------
| -n | --nocolor | strips the output free of ascii color escape sequences

## `enviroment`
Takes 2 mandatory argument: user, session id; and prints the *initial* enviroment
of the corresponding session in prettified json.

There is one option available which accepts no arguments:

| Short | Long | Meaning
|-------|------|----------
| -m | --minify | print the enviroment in minified json

## `timestamps`
Takes 2 mandatory argument: user, session id; and prints the timestamps of the
session.

## Configuration
The file path must be `$XDG_CONFIG_HOME/.config/xhronicle/config`.
<br/>
If `$XDG_CONFIG_HOME` is not set, it defaults to `~/.config/`.

A simple configuration file is needed to specify the following:
- Users' names and corresponding paths to the xonsh history directory
- Timedate format for `--begin` and `--end` options of `print` command
- Timedate format for `--from` and `--till` options of `print` command
- Duration format (in the future)
- Colors (in the future)

A simple `.ini`-like format is used according to [this specification](https://nim-lang.org/docs/times.html).

Example:
``` ini
[Users]
root: "/root/.local/share/xonsh"
sealmove: "/home/sealmove/.local/share/xonsh"

[PrintFormat]
separator: " | "

[TimeFormat]
print: "dd MMM YYYY hh:mm:ss"
parse: "yyyy-M-d-h:m:s"

[Colors]
separator: lightYellow
user: green
sessionid: lightGreen
commandindex: cyan
returncode: magenta
begin: yellow
end: lightYellow
duration: red
```

Valid colors are: black, white, red, green, yellow, blue, magenta, cyan, gray.
You can prefix any of them (except black and white) with `light` and use camel
case (for example `lightBlue`) to get a lighter hue.

## How to generate binary
* Clone
* [Install Nim](https://nim-lang.org/install.html)
* Compile (`nim c -d:release -o:xhronicle xhronicle.nim`) 

## Roadmap
- [ ] Better error messages
- [ ] Custom duration format
- [ ] Flexible input for `--from` and `--till` options of `print`
- [ ] Print enviroment variables specific to a command (hard to implement)
- [x] A help command
- [x] Colored output for `print`
- [x] Configuration system
- [x] `--nocolor` option for `output` command
- [x] `--minify` option for `enviroment` command

## Notes
The program will obviously print commands according to the privilege of the
user that ran the command. For example running the command as a user other
than root will not print the commands ran by root.
