import parseopt, parseutils, strutils, os, json, algorithm, times, math,
  strformat

type CmdInfo = tuple
  ts: float
  sid, idx: int

const
  xonfig = [
    (name: "root", path: "/root/.local/share/xonsh"),
    (name: "sealmove", path: "/home/sealmove/.local/share/xonsh")
  ]
  defaultTimePrintFormat = "dd MMM YYYY hh:mm:ss"
  defaultTimeParseFormat = "yyyy-M-d-h:m:s"

var
  sessions: seq[tuple[user: string, data: JsonNode]]
  commands: seq[CmdInfo]

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

proc lookup(sid, idx: int, what: FieldKind): Field =
  try:
    case what
    of fkInp:
      let input = getStr(sessions[sid][1]["cmds"][idx]["inp"])
      result = Field(kind: fkInp, strVal: input)
    of fkOut:
      let output = getStr(sessions[sid][1]["cmds"][idx]["out"])
      result = Field(kind: fkInp, strVal: output)
    of fkEnv:
      result = Field(kind: fkEnv, env: sessions[sid][1]["env"])
    of fkUser:
      let user = sessions[sid][0]
      result = Field(kind: fkUser, strVal: user)
    of fkId:
      let id = getStr(sessions[sid][1]["sessionid"])
      result = Field(kind: fkId, strVal: id)
    of fkRtn:
      let rtn = getInt(sessions[sid][1]["cmds"][idx]["rtn"])
      result = Field(kind: fkRtn, intVal: rtn)
    of fkBeg:
      let ts = sessions[sid][1]["cmds"][idx]["ts"]
      result = Field(kind: fkBeg, time: initTime(ts[0]))
    of fkEnd:
      let ts = sessions[sid][1]["cmds"][idx]["ts"]
      result = Field(kind: fkEnd, time: initTime(ts[1]))
    of fkDur:
      let ts = sessions[sid][1]["cmds"][idx]["ts"]
      let dur = getFloat(ts[1]) - getFloat(ts[0])
      result = Field(kind: fkDur, duration: dur)
  except:
    discard # XXX: log error

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
        optConfig.fromm = parseTime(val, defaultTimeParseFormat, local())
      of "till", "t":
        optConfig.till = parseTime(val, defaultTimeParseFormat, local())
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

  for entry in xonfig:
    if optConfig.session.flag:
      try:
        let file = entry.path / "xonsh-" & optConfig.session.sid & ".json"
        sessions.add((entry.name, parseFile(file)["data"]))
      except:
        discard # XXX: log error
    else:
      for file in walkFiles(entry.path / "*.json"):
        try:
          sessions.add((entry.name, parseFile(file)["data"]))
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
        str &= lookup(cmd.sid, cmd.idx, fkUser).strVal & "\t"
      of poId:
        str &= lookup(cmd.sid, cmd.idx, fkId).strVal & "[" & &"{cmd.idx:03}" & "]\t"
      of poRtn:
        str &= $lookup(cmd.sid, cmd.idx, fkRtn).intVal & "\t"
      of poBeg:
        let beg = lookup(cmd.sid, cmd.idx, fkBeg).time
        str &= beg.format(defaultTimePrintFormat) & "\t"
      of poEnd:
        let endd = lookup(cmd.sid, cmd.idx, fkEnd).time
        str &= endd.format(defaultTimePrintFormat) & "\t"
      of poDur:
        let
          dur = lookup(cmd.sid, cmd.idx, fkDur).duration
        str &= &"{dur:>7.2f}" & "s\t"
    stdout.write(str & lookup(cmd.sid, cmd.idx, fkInp).strVal)

elif "output".startsWith(paramStr(1)):
  if paramCount() != 4:
    echo "This commands takes exactly 3 arguments"
    quit QuitFailure
  # Find user's history directory
  var path: string
  for x in xonfig:
    if x.name == paramStr(2):
      path = x.path
      break
  if path == "":
    echo "User not found"
    quit QuitFailure
  let file = path / "xonsh-" & paramStr(3) & ".json"
  var
    command: JsonNode
    output: string
    idx: int
  try:
    idx = parseInt(paramStr(4))
  except ValueError:
    echo "Could not parse command index"
    quit QuitFailure
  try:
    command = parseFile(file)["data"]["cmds"][idx]
  except:
    echo "Json error"
    quit QuitFailure
  try:
    output = getStr(command["out"])
  except KeyError:
    echo "Output of command not found (maybe output logging was not " &
      "enabled in xonsh at the time?)"
    quit QuitFailure
  echo output

elif "enviroment".startsWith(paramStr(1)):
  if paramCount() != 3:
    echo "This commands takes exactly 2 arguments"
    quit QuitFailure
  # Find user's history directory
  var path: string
  for x in xonfig:
    if x.name == paramStr(2):
      path = x.path
      break
  if path == "":
    echo "User not found"
    quit QuitFailure
  let file = path / "xonsh-" & paramStr(3) & ".json"
  var enviroment: JsonNode
  try:
    enviroment = parseFile(file)["data"]["env"]
  except:
    echo "Json error"
    quit QuitFailure
  echo pretty(enviroment)

elif "timestamps".startsWith(paramStr(1)):
  if paramCount() != 3:
    echo "This commands takes exactly 2 arguments"
    quit QuitFailure
  # Find user's history directory
  var path: string
  for x in xonfig:
    if x.name == paramStr(2):
      path = x.path
      break
  if path == "":
    echo "User not found"
    quit QuitFailure
  let file = path / "xonsh-" & paramStr(3) & ".json"
  var ts: JsonNode
  try:
    ts = parseFile(file)["data"]["ts"]
  except:
    echo "Json error"
    quit QuitFailure
  let
    beg = initTime(ts[0])
    endd = initTime(ts[1])
    dur = getFloat(ts[1]) - getFloat(ts[0])
  var str: string
  str &= beg.format(defaultTimePrintFormat) & "\t"
  str &= endd.format(defaultTimePrintFormat) & "\t"
  str &= &"({dur:.2f}" & "s)\t"
  echo str

else:
  echo "Command not found"
  quit QuitFailure
