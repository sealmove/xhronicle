import
  os, streams, algorithm, math, re, parseopt, parsecfg, json, times,
  parseutils, strutils, strformat

type CmdInfo = tuple
  ts: float
  sidx, cidx: int

const defaultColor = "\e[39m"

var
  xonfig = getConfigDir() / "xhronicle" / "config"
  currSection: string
  users: seq[tuple[name, path: string]]
  printTimeFormat, parseTimeFormat, printSeparator: string
  colors: tuple[s, u, i, x, r, b, e, d: string]
  sessions: seq[tuple[user: string, data: JsonNode]]
  commands: seq[CmdInfo]

if existsFile(xonfig):
  proc getColor(c: string): string =
    let code = case c
               of "black": 30
               of "red": 31
               of "lightRed": 91
               of "green": 32
               of "lightGreen": 92
               of "yellow": 33
               of "lightYellow": 93
               of "blue": 34
               of "lightBlue": 94
               of "magenta": 35
               of "lightMagenta": 95
               of "cyan": 36
               of "lightCyan": 96
               of "gray": 90
               of "lightGray": 37
               of "white": 97
               else:
                 echo "Unknown color"
                 echo c
                 quit QuitFailure
    result = &"\e[{code}m"
  var
    f = newFileStream(xonfig, fmRead)
    p: CfgParser
  open(p, f, xonfig)
  while true:
    var e = next(p)
    case e.kind
    of cfgEof: break
    of cfgSectionStart:
      currSection = e.section
    of cfgKeyValuePair:
      case currSection
      of "Users":
        users.add((e.key, e.value))
      of "PrintFormat":
        case e.key
        of "separator":
          printSeparator = e.value
        else:
          echo "Unknown config option"
          quit QuitFailure
      of "TimeFormat":
        case e.key
        of "print":
          printTimeFormat = e.value
        of "parse":
          parseTimeFormat = e.value
        else:
          echo "Unknown config option"
          quit QuitFailure
      of "Colors":
        case e.key
        of "separator":
          colors.s = getColor(e.value)
        of "user":
          colors.u = getColor(e.value)
        of "sessionid":
          colors.i = getColor(e.value)
        of "commandindex":
          colors.x = getColor(e.value)
        of "returncode":
          colors.r = getColor(e.value)
        of "begin":
          colors.b = getColor(e.value)
        of "end":
          colors.e = getColor(e.value)
        of "duration":
          colors.d = getColor(e.value)
        else:
          echo "Unknown color option"
          quit QuitFailure
      else:
        echo "Unknown config section"
        quit QuitFailure
    of cfgOption:
      discard
    of cfgError:
      echo(e.msg)
  close(p)
else:
  echo "Using default configuration"
  users.add((getEnv("USER"), getHomeDir() / ".local/share/xonsh"))
  printTimeFormat = "dd MMM YYYY hh:mm:ss"
  parseTimeFormat = "yyyy-M-d-h:m:s"
  colors.s = "\e[39m"
  colors.u = "\e[39m"
  colors.i = "\e[39m"
  colors.x = "\e[39m"
  colors.r = "\e[39m"
  colors.b = "\e[39m"
  colors.e = "\e[39m"
  colors.d = "\e[39m"

printSeparator = colors.s & printSeparator & defaultColor

proc initTime(time: JsonNode): Time =
  let (sec, nanosec) = splitDecimal(getFloat(time))
  result = initTime(int64(sec), int64(1_000_000_000 * nanosec))

type
  FieldKind = enum
    fkInp
    fkOut
    fkEnv
    fkUser
    fkId
    fkRtn
    fkBeg
    fkEnd
    fkDur
  Field = ref FieldObj
  FieldObj = object
    case kind: FieldKind
    of fkInp, fkOut, fkUser, fkId: strVal: string
    of fkRtn: intVal: int
    of fkBeg, fkEnd: time: Time
    of fkDur: duration: float
    of fkEnv: env: JsonNode

proc lookup(sidx, cidx: int, what: FieldKind): Field =
  try:
    case what
    of fkInp:
      let input = getStr(sessions[sidx][1]["cmds"][cidx]["inp"])
      result = Field(kind: fkInp, strVal: input)
    of fkOut:
      let output = getStr(sessions[sidx][1]["cmds"][cidx]["out"])
      result = Field(kind: fkInp, strVal: output)
    of fkEnv:
      result = Field(kind: fkEnv, env: sessions[sidx][1]["env"])
    of fkUser:
      let user = sessions[sidx][0]
      result = Field(kind: fkUser, strVal: user)
    of fkId:
      let id = getStr(sessions[sidx][1]["sessionid"])
      result = Field(kind: fkId, strVal: id)
    of fkRtn:
      let rtn = getInt(sessions[sidx][1]["cmds"][cidx]["rtn"])
      result = Field(kind: fkRtn, intVal: rtn)
    of fkBeg:
      let ts = sessions[sidx][1]["cmds"][cidx]["ts"]
      result = Field(kind: fkBeg, time: initTime(ts[0]))
    of fkEnd:
      let ts = sessions[sidx][1]["cmds"][cidx]["ts"]
      result = Field(kind: fkEnd, time: initTime(ts[1]))
    of fkDur:
      let ts = sessions[sidx][1]["cmds"][cidx]["ts"]
      let dur = getFloat(ts[1]) - getFloat(ts[0])
      result = Field(kind: fkDur, duration: dur)
  except:
    discard # XXX: log error

proc path(user, sid: string): string =
  var filePath: string
  for u in users:
    if u.name == user:
      filePath = u.path
      break
  if filePath == "":
    echo "User not found"
    quit QuitFailure
  result = filePath / "xonsh-" & sid & ".json"

if "print".startsWith(paramStr(1)):
  type
    Config = tuple
      # Filter options
      session: tuple[flag: bool, sid: string]
      fromm, till: Time
      # Print options (ordered)
      print: seq[tuple[order: int, option: PrintOption]]
      # Other options
      strip: bool
    PrintOption = enum
      poUser
      poId
      poRtn
      poBeg
      poEnd
      poDur

  const
    shorts = {'u', 'i', 'r', 'b', 'e', 'd', 'n'}
    longs = @["user", "id", "returncode", "begin", "end", "duration",
      "nocolor"]
  var
    isFirstIter = true
    i: int
    optConfig: Config
  
  optConfig.till = fromUnix(int64.high)

  for kind, key, val in getopt(shortNoVal = shorts, longNoVal = longs):
    if isFirstIter:
      isFirstIter = false
      continue
    case kind
    of cmdShortOption, cmdLongOption:
      case key
      of "session", "s":
        optConfig.session = (true, val)
      of "from", "f":
        optConfig.fromm = parseTime(val, parseTimeFormat, local())
      of "till", "t":
        optConfig.till = parseTime(val, parseTimeFormat, local())
      of "user", "u":
        optConfig.print.add((i, poUser))
      of "id", "i":
        optConfig.print.add((i, poId))
      of "returncode", "r":
        optConfig.print.add((i, poRtn))
      of "begin", "b":
        optConfig.print.add((i, poBeg))
      of "end", "e":
        optConfig.print.add((i, poEnd))
      of "duration", "d":
        optConfig.print.add((i, poDur))
      of "nocolor", "n":
        optConfig.strip = true
      else:
        echo "Error while parsing option"
        quit QuitFailure
    of cmdArgument:
      echo "This command does not accept arguments"
      quit QuitFailure
    of cmdEnd:
      assert(false)
    inc i
  
  sort(optConfig.print)

  for entry in users:
    if optConfig.session.flag:
      try:
        let filePath = entry.path / "xonsh-" & optConfig.session.sid & ".json"
        sessions.add((entry.name, parseFile(filePath)["data"]))
      except:
        echo "The provided session id for filtering didn't check out (-s flag)"
        quit QuitFailure
    else:
      for filePath in walkFiles(entry.path / "*.json"):
        try:
          sessions.add((entry.name, parseFile(filePath)["data"]))
        except:
          discard # XXX: log error

  for i, session in sessions:
    var j = 0
    for cmd in session.data["cmds"]:
      if getFloat(cmd["ts"][0]).int64 > optConfig.fromm.toUnix and
         getFloat(cmd["ts"][0]).int64 < optConfig.till.toUnix:
        commands.add((getFloat(cmd["ts"][0]), i, j))
        inc j

  sort(commands)

  for cmd in commands:
    var str: string
    for p in optConfig.print:
      case p.option
      of poUser:
        str &= colors.u & $lookup(cmd.sidx, cmd.cidx, fkUser).strVal &
          defaultColor & printSeparator
      of poId:
        str &= colors.i & $lookup(cmd.sidx, cmd.cidx, fkId).strVal &
          defaultColor & "[" & colors.x & &"{cmd.cidx:03}" & defaultColor &
          "]" & printSeparator
      of poRtn:
        let rtn = lookup(cmd.sidx, cmd.cidx, fkRtn).intVal
        str &= colors.r & &"{rtn:3}" &
          defaultColor & printSeparator
      of poBeg:
        let beg = lookup(cmd.sidx, cmd.cidx, fkBeg).time
        str &= colors.b & beg.format(printTimeFormat) & defaultColor &
          printSeparator
      of poEnd:
        let endd = lookup(cmd.sidx, cmd.cidx, fkEnd).time
        str &= colors.e & endd.format(printTimeFormat) & defaultColor &
          printSeparator
      of poDur:
        let dur = lookup(cmd.sidx, cmd.cidx, fkDur).duration
        str &= colors.d & &"{dur:>8.2f}" & defaultColor & "s" & printSeparator
    if optConfig.strip:
      str = str.replace(re"\x1b\[[0-9;]*m")
    stdout.write(str & lookup(cmd.sidx, cmd.cidx, fkInp).strVal)

elif "output".startsWith(paramStr(1)):
  var
    command: JsonNode
    user: string
    sid: string
    cidx: int
    output: string
    isFirstIter = true
    argIdx: int
    stripOpt: bool

  for kind, key, val in getopt(shortNoVal = {'n'}, longNoVal = @["nocolor"]):
    if isFirstIter:
      isFirstIter = false
      continue
    case kind
    of cmdShortOption, cmdLongOption:
      case key
      of "nocolor", "n":
        stripOpt = true
      else:
        echo "Error while parsing option"
        quit QuitFailure
    of cmdArgument:
      case argIdx
      of 0: user = key
      of 1: sid = key
      of 2:
        try:
          cidx = parseInt(key)
        except ValueError:
          echo "Could not parse command index"
          quit QuitFailure
      else:
        echo "This command takes exactly 3 arguments"
        quit QuitFailure
      inc argIdx
    of cmdEnd:
      assert(false)

  try:
    command = parseFile(path(user, sid))["data"]["cmds"][cidx]
  except:
    echo "Json error"
    quit QuitFailure
  try:
    output = getStr(command["out"])
  except KeyError:
    echo "Output of command not found (maybe output logging was not " &
      "enabled in xonsh at the time?)"
    quit QuitFailure

  if stripOpt:
    output = output.replace(re"\x1b\[[0-9;]*m")

  echo output

elif "enviroment".startsWith(paramStr(1)):
  var
    enviroment: JsonNode
    user: string
    sid: string
    isFirstIter = true
    argIdx: int
    minifyOpt: bool

  for kind, key, val in getopt(shortNoVal = {'m'}, longNoVal = @["minify"]):
    if isFirstIter:
      isFirstIter = false
      continue
    case kind
    of cmdShortOption, cmdLongOption:
      case key
      of "minify", "m":
        minifyOpt = true
      else:
        echo "Error while parsing option"
        quit QuitFailure
    of cmdArgument:
      case argIdx
      of 0: user = key
      of 1: sid = key
      else:
        echo "This command takes exactly 2 arguments"
        quit QuitFailure
      inc argIdx
    of cmdEnd:
      assert(false)

  try:
    enviroment = parseFile(path(user, sid))["data"]["env"]
  except:
    echo "Json error"
    quit QuitFailure
  if minifyOpt:
    echo enviroment
  else:
    echo pretty(enviroment)

elif "timestamps".startsWith(paramStr(1)):
  if paramCount() != 3:
    echo "This commands takes exactly 2 arguments"
    quit QuitFailure
  let filePath = path(paramStr(2), paramStr(3))
  var ts: JsonNode
  try:
    ts = parseFile(filePath)["data"]["ts"]
  except:
    echo "Json error"
    quit QuitFailure
  let
    beg = initTime(ts[0])
    endd = initTime(ts[1])
    dur = getFloat(ts[1]) - getFloat(ts[0])
  var str: string
  str &= beg.format(printTimeFormat) & printSeparator
  str &= endd.format(printTimeFormat) & printSeparator
  str &= &"({dur:.2f}" & "s)" & printSeparator
  echo str

elif "help".startsWith(paramStr(1)):
  echo readFile("help.txt")

else:
  echo "Command not found"
  quit QuitFailure
