import std/os
import std/osproc
import std/strutils
import std/sugar
import std/terminal

import version

const
  helpParts = slurp("assets/help.txt").split("*****\n")
  help = helpParts[0].strip
    .replace("__version", panVersion)
    .replace("__compileDate", CompileDate)
  reference = helpParts[1].strip

  typeMarker = "  ::type"

var
  gHelpPager*: string
  gHelpPagerArgs* = "-fR"

proc printFormattedHelp(outfile: File, text: string) =

  template output(style: varargs[untyped]) =
    outfile.styledWriteLine style

  for rawLine in text.splitLines:
    let
      isType = rawLine.endsWith(typeMarker)
      line = rawLine.dup(removeSuffix(typeMarker))
    if rawLine.len > 0:
      case line[0]
      of '#':  # headers
        output fgGreen, styleBright, line[1..^1]
      of '|':  # lists with descriptions
        let
          leadingws = line[1..^1].indentation
          parts = line[leadingws..^1].split("  ", maxsplit = 1)
          indent = leadingws.spaces
        output fgCyan, " ", indent, parts[0][1..^1],
                   resetStyle, "  ", parts[1]
      of ';':  # lists without descriptions
        output fgCyan, " ", line[1..^1]
      of '>':  # functions, types
        if isType:
          output styleBright, fgCyan, "  ", styleUnderscore, line[2..^1]
        else:
          output styleBright, fgMagenta, " ", line[1..^1]
      else:
        output line
    else:
      output line

proc getPager(): string =

  result = findExe(
    if gHelpPager.len > 0: gHelpPager
    elif existsEnv("PAN_PAGER"): getEnv("PAN_PAGER")
    elif existsEnv("PAGER"): getEnv("PAGER")
    elif existsEnv("MAN_PAGER"): getEnv("MAN_PAGER")
    elif findExe("less").len > 0: "less"
    else: ""
  )

when defined(posix):
  from posix import mkstemp

proc pageFormattedHelp(text: string) =

  when defined(posix):

    let pagerName = getPager()
    if pagerName.len > 0:
      let
        helpFilename = "/tmp/panreference.XXXXXX"
        helpFd = mkstemp(helpFilename.cstring).FileHandle
      var
        helpFile: File
      doAssert helpFile.open(helpFd, fmWrite)
      helpFile.printFormattedHelp(text)
      helpFile.close()

      let
        pagerExe = findExe(pagerName)
        pagerProcess = startProcess(
          command = pagerExe,
          args = gHelpPagerArgs.split(' ').dup(add(helpFilename)),
          options = {poParentStreams}
        )

      discard pagerProcess.waitForExit()
      close pagerProcess

      removeFile(helpFilename)
    else:
      stdout.printFormattedHelp text

  else:
    stdout.printFormattedHelp text

proc queryReferenceAux(file: File, phrase: string): bool =

  const referenceLines = reference.splitLines

  type
    QueryKind = enum
      InvalidQuery
      Global
      Field
      Method

  var
    kind = InvalidQuery
    left, right: string

  if phrase.len == 0: return
  if phrase.startsWith("pan."):
    kind = Global
  elif '.' in phrase:
    let parts = phrase.split('.', maxsplit = 1)
    kind = Field
    (left, right) = (parts[0], parts[1])
  elif ':' in phrase:
    let parts = phrase.split(':', maxsplit = 1)
    kind = Method
    (left, right) = (parts[0], parts[1])
  else:
    kind = Global

  if kind == InvalidQuery: return

  let namespacedPhrase =
    if phrase.startsWith("pan."): phrase
    else: "pan." & phrase

  var
    findings: string
    currentType, typeLine: string
    startingLineIndent = -1
    i = 0

  while i < referenceLines.len:

    let rawLine = referenceLines[i]

    # remove directive noise
    let
      isSynopsis = rawLine.startsWith("> ")
      isTable = rawLine.startsWith("| ")
    var line = rawLine
    line.removePrefix("> ")
    line.removePrefix("| ")
    line.removePrefix("; ")
    let lineIndent = line.indentation
    line = line.strip

    # if we haven't found a matching doc yet
    if startingLineIndent == -1:
      # see if the line matches the phrase
      case kind
      of Global:
        if isSynopsis and namespacedPhrase in rawLine:
          startingLineIndent = lineIndent
          findings.add(rawLine & '\n')
      of Field:
        if isTable and line.startsWith('.' & right):
          findings.add(rawLine & '\n')
      of Method:
        if isSynopsis and currentType == left and line.startsWith(':' & right):
          startingLineIndent = lineIndent
          findings.add(rawLine & '\n')
      else: doAssert false

    # if we have a doc, then we add it to the findings
    elif lineIndent > startingLineIndent:
      findings.add(rawLine & '\n')
    elif lineIndent <= startingLineIndent:
      startingLineIndent = -1
      continue

    # check for the type marker
    if line.endsWith(typeMarker):
      line.removeSuffix(typeMarker)
      currentType = line
      if currentType == left:
        typeLine = rawLine

    inc i

  stripLineEnd findings
  if findings.len == 0: return
  if typeLine.len > 0:
    findings.insert(typeLine & '\n', 0)

  file.printFormattedHelp findings
  result = true

proc queryReference*(file: File, phrases: seq[string]): bool =

  result = true
  var failedCount = 0

  for i, phrase in phrases:
    file.styledWriteLine fgGreen, "results for ",
                         styleUnderscore, fgWhite, phrase, resetStyle, ":"
    if not stdout.queryReferenceAux(phrase):
      file.styledWriteLine fgYellow, "  no matches found."
      inc failedCount
      result = false
    if i < phrases.high:
      file.write('\n')

  if failedCount > 0:
    file.styledWriteLine $failedCount, fgYellow, " queries failed."

proc printHelp*() =
  stdout.printFormattedHelp help

proc printReference*() =
  pageFormattedHelp reference

