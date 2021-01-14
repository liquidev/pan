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

proc printHelp*() =
  stdout.printFormattedHelp help

proc printReference*() =
  pageFormattedHelp reference
