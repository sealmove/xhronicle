import parseopt, strutils, os, json, algorithm, times, math, strformat

type
  CmdInfo = tuple[ts: float, sid, cid: int]

const
  config = [
    ("root", "/root/.local/share/xonsh"),
    ("sealmove", "/home/sealmove/.local/share/xonsh")
  ]
  defaultTimeFormat = "dd MMM YYYY hh:mm:ss"

var sessions: seq[tuple[user: string, data: JsonNode]]
for entry in config:
  for file in walkFiles(entry[1] / "*.json"):
    try:
      sessions.add((entry[0], parseFile(file)["data"]))
    except:
      discard # XXX: log error

var commands: seq[CmdInfo]
for i, session in sessions:
  var j = 0 # XXX: find better way
  for cmd in session[1]["cmds"]:
    commands.add((getFloat(cmd["ts"][0]), i, j))
    inc j

sort(commands)

type
  FieldKind = enum
    fkInp
    fkOut
    fkRtn
    fkStrt
    fkFin
    fkDur
    fkEnv
    fkUser
    fkId
  Field = ref FieldObj
  FieldObj = object
    case kind: FieldKind
    of fkInp, fkOut, fkUser, fkId: strVal: string
    of fkRtn: intVal: int
    of fkStrt, fkFin: time: Time
    of fkDur: duration: float
    of fkEnv: env: JsonNode

proc lookup(sid, cid: int, what: FieldKind): Field =
  try:
    case what
    of fkInp:
      let input = getStr(sessions[sid][1]["cmds"][cid]["inp"])
      result = Field(kind: fkInp, strVal: input)
    of fkOut:
      let output = getStr(sessions[sid][1]["cmds"][cid]["out"])
      result = Field(kind: fkInp, strVal: output)
    of fkRtn:
      let rtn = getInt(sessions[sid][1]["cmds"][cid]["rtn"])
      result = Field(kind: fkRtn, intVal: rtn)
    of fkStrt:
      let
        ts = sessions[sid][1]["cmds"][cid]["ts"]
        (startSec, startNano) = splitDecimal(getFloat(ts[0]))
        start = initTime(int64(startSec), int64(1_000_000_000 * startNano))
      result = Field(kind: fkStrt, time: start)
    of fkFin:
      let
        ts = sessions[sid][1]["cmds"][cid]["ts"]
        (finishSec, finishNano) = splitDecimal(getFloat(ts[1]))
        finish = initTime(int64(finishSec), int64(1_000_000_000 * finishNano))
      result = Field(kind: fkFin, time: finish)
    of fkDur:
      let ts = sessions[sid][1]["cmds"][cid]["ts"]
      let dur = getFloat(ts[1]) - getFloat(ts[0])
      result = Field(kind: fkDur, duration: dur)
    of fkEnv:
      result = Field(kind: fkEnv, env: sessions[sid][1]["env"])
    of fkUser:
      let user = sessions[sid][0]
      result = Field(kind: fkUser, strVal: user)
    of fkId:
      let id = getStr(sessions[sid][1]["sessionid"])
      result = Field(kind: fkId, strVal: id)
  except:
    discard # XXX: log error

if paramCount() == 0:
  quit QuitFailure

type OrderedOption = enum
  ooUser
  ooId
  ooRtn
  ooStrt
  ooFin
  ooDur

if "print".startsWith(paramStr(1)):
  var
    isFirstIter = true
    orderedOpts: seq[tuple[order: int, option: OrderedOption]]
    optStrip: bool
    i: int
  const
    shorts = {'u', 'i', 'r', 's', 'f', 'd', 'n'}
    longs = @["user", "id", "returncode", "nocolor", "start", "finish",
      "duration"]
  for kind, key, val in getopt(shortNoVal = shorts, longNoVal = longs):
    if isFirstIter:
      isFirstIter = false
      continue
    case kind
    of cmdArgument:
      discard
    of cmdShortOption, cmdLongOption:
      case key
      of "user", "u":
        orderedOpts.add((i, ooUser))
      of "id", "i":
        orderedOpts.add((i, ooId))
      of "returncode", "r":
        orderedOpts.add((i, ooRtn))
      of "start", "s":
        orderedOpts.add((i, ooStrt))
      of "finish", "f":
        orderedOpts.add((i, ooFin))
      of "duration", "d":
        orderedOpts.add((i, ooDur))
      of "nocolor", "n":
        optStrip = true
      else:
        echo "Error while parsing option"
        quit 0
    of cmdEnd:
      assert(false)
    inc i
  sort(orderedOpts)
  for cmd in commands:
    var str: string
    for oo in orderedOpts:
      case oo[1]
      of ooUser:
        str &= lookup(cmd[1], cmd[2], fkUser).strVal & "\t"
      of ooId:
        str &= lookup(cmd[1], cmd[2], fkId).strVal & "[" & $cmd[2] & "]\t"
      of ooRtn:
        str &= $lookup(cmd[1], cmd[2], fkRtn).intVal & "\t"
      of ooStrt:
        let start = lookup(cmd[1], cmd[2], fkStrt).time
        str &= start.format(defaultTimeFormat) & "\t"
      of ooFin:
        let finish = lookup(cmd[1], cmd[2], fkFin).time
        str &= finish.format(defaultTimeFormat) & "\t"
      of ooDur:
        let
          dur = lookup(cmd[1], cmd[2], fkDur).duration
        str &= &"{dur:>7.2f}" & "s\t"
    stdout.write(str & lookup(cmd[1], cmd[2], fkInp).strVal)
elif "returncode".startsWith(paramStr(1)):
  if paramCount() != 3:
    quit QuitFailure
elif "output".startsWith(paramStr(1)):
  discard # XXX
elif "enviroment".startsWith(paramStr(1)):
  discard # XXX
else:
  discard # XXX: print error command not found
