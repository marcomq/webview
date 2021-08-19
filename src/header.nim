import nimterop/[build, cimport]
import strutils, regex

when defined(linux):
  discard
  {.passL: staticExec"pkg-config --libs gtk+-3.0 webkit2gtk-4.0".}
  # {.passC: staticExec"pkg-config --cflags gtk+-3.0 webkit2gtk-4.0".}
elif defined(windows):
  {.fatal: "Not implemented".}
elif defined(macosx):
  {.fatal: "Not implemented".}

when not defined(cpp):
  {.fatal: "Webview requires cpp backend! Compile with: \"nim cpp filename.nim\"".}

static:
  when defined(printWrapper):
    cDebug()                                                # Print wrapper to stdout

const
  baseDir = getProjectCacheDir("webview_new")             # Download library within nimcache

# getHeader(
#   "webview.h",                                             # The header file to wrap, full path is returned in `headerPath`
#   giturl = "https://github.com/webview/webview.git",            # Git repo URL
#   outdir = baseDir,                                       # Where to download/build/search
#   # conFlags = "--disable-comp --enable-feature",           # Flags to pass configure script
#   # cmakeFlags = "-DENABLE_STATIC_LIB=ON"                   # Flags to pass to Cmake
#   # altNames = "hdr"                                        # Alterate names of the library binary, full path returned in `headerLPath`
# )
static:
  discard staticExec "git clone https://github.com/webview/webview.git " & baseDir
  discard staticExec "cd " & baseDir & " && " & "git checkout master"

# Wrap headerPath as returned from getHeader() and link statically
# or dynamically depending on user input
# when not isDefined(headerStatic):
#   cImport(headerPath, recurse = true, dynlib = "headerLPath")       # Pass dynlib if not static link
# else:
# cPassC("-xc++")
# cPassL("-xc++")


static:
#   cAddStdDir(mode = "cpp")
#   echo baseDir/"webview.h"
  for f in [baseDir/"webview.h"]:
    for i in [
      ("\n#define WEBVIEW_API extern\n", "\n#define WEBVIEW_API extern inline\n"),
#       ("sync_binding_t", "string")
    ]:
      f.writeFile f.readFile.replace(i[0], i[1])

proc getPkgconfigDirs(pkgconfigOutput: static string): static seq[string] =
  for m in pkgconfigOutput.findAll(re"-I([^ ]+)"):
    result.add m.group(0, pkgconfigOutput)

const pkgconfigFlags = 
  staticExec("pkg-config --cflags gtk+-3.0 webkit2gtk-4.0").
    replace("-pthread", "")

# cPassC(pkgconfigFlags)
# static:
#   echo pkgconfigFlags.getPkgconfigDirs()
  # Remove C++ methods

cPlugin:
  import strutils

  const skipSymbols =
      @["window", "run", "terminate", "dispatch", "set_size", "set_title",
        "navigate", "init", "eval", "bind", "on_message", "resolve",
        "hex2nibble", "hex2char", "json_parse_c", "json_unescape"
      ]

  proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
    case sym.kind
      of nskProc:
        if sym.name in skipSymbols:
          sym.name = ""
        else:
          sym.name = sym.name.replace("webview_", "")
      of nskType:
        if sym.name == "webview_t":
          sym.name = "Webview"
      else:
        discard
    # sym.name = ""
    # sym.name = sym.name.strip(chars={'_'}).replace("__", "_")
#     for i in ["G_DATE", "G_HOOK_FLAG", "G_CSET_a", "G_LIST_"]:
#       if sym.name.find(i) != -1:
#         sym.name &= "2"

# cOverride:
#   proc resolve*(seq: string; status: cint; result: string)

cIncludeDir(pkgconfigFlags.getPkgconfigDirs())

cImport(baseDir/"webview.h", recurse = false, mode = "cpp", flags = "")

# proc resolve*(seq: string; status: cint; result: string) {.importc, cdecl, impwebviewHdr.}
# {.passL: "-DWEBVIEW_H".}
# {.passC: "-DWEBVIEW_H".}
