import json, std/jsonutils, macros, tables, strutils, strformat, sequtils, random
import header

# export header

proc randomString(): string =
  randomize()
  const lowerCaseAscii = 97..122
  32.newSeqWith(lowerCaseAscii.rand.char).join

type 
  # Webview* = pointer
  WindowSizeHint* {.pure.} = enum 
    None = WEBVIEW_HINT_NONE
    Min = WEBVIEW_HINT_MIN
    Max = WEBVIEW_HINT_MAX
    Fixed = WEBVIEW_HINT_FIXED

proc newWebView*(debug: bool, window: Webview): Webview =
  create(debug.cint, window)

proc newWebView*(debug: bool): Webview =
  create(debug.cint, nil)

proc exit*(w: Webview) =
  w.destroy()

proc set_size*(w: Webview; width: int; height: int; hint: WindowSizeHint) =
  ## Updates native window size.
  ## Available hints:
  ##   WindowSizeHint.None - Width and height are default size
  ##   WindowSizeHint.Min - Width and height are minimum bounds
  ##   WindowSizeHint.Max - Width and height are maximum bounds
  ##   WindowSizeHint.Fixed - Window size can not be changed by a user
  set_size(w, width.cint, height.cint, hint.cint)

proc newWebView*(title="WebView", url="", 
                width=640, height=480, 
                resizable=true, debug=false,
                cb: pointer = nil): Webview =
  result = newWebView(debug)
  result.set_title(title)
  result.navigate(url)
  let hint = if resizable: WindowSizeHint.None
    else: WindowSizeHint.Fixed
  result.set_size(width = width, height = height, hint = hint)
  assert cb == nil, "Not implemented"

type
  ProcA1R = proc(req: JsonNode): JsonNode
  ArgTuple = tuple[w: Webview, p: ProcA1R]

var dispatchTable = newTable[int, ArgTuple]()

proc wrapProc(seq: cstring, req: cstring, arg: pointer) {.cdecl.} =
  var argUnref = dispatchTable[cast[int](arg)]
  let
    w = argUnref.w
    p = argUnref.p
  try:
    let output = $ p(parseJson($req))
    w.`return`(seq, 0.cint, output.cstring)
  except:
    let
      e = getCurrentException()
      msg = getCurrentExceptionMsg()
      jsonMsg = $ %*(
        fmt"""Exception "{e.name}" occured: {msg}""" & "\n" &
        fmt"Stacktrace: {e.getStacktrace()}"
      )
    w.`return`(seq, 1.cint, jsonMsg.cstring)

proc bindProc*(w: Webview, name: string, p: ProcA1R) =
  let i = dispatchTable.len() + 1
  dispatchTable[i] = (w, p)
  w.`bind`(name, wrapProc, cast[pointer](i))

proc bindProc*(w: Webview, name: string, p: proc(req: JsonNode)) =
  proc wrap(req: JsonNode): JsonNode =
    p(req)
    return %*[]
  bindProc(w, name, wrap)

proc bindProc*(w: Webview, name: string, p: proc(): JsonNode) =
  proc wrap(req: JsonNode): JsonNode =
    return p()
  bindProc(w, name, wrap)

proc bindProc*(w: Webview, name: string, p: proc()) =
  proc wrap(req: JsonNode): JsonNode =
    p()
    return %*[]
  bindProc(w, name, wrap)

proc bindProc*[A1,R](w: Webview, name: string, p: proc(arg1: A1): R) =
  proc wrap(arg1: JsonNode): JsonNode =
    return p(arg1[0].jsonTo(A1)).toJson()
  bindProc(w, name, wrap)

proc bindProc*[R](w: Webview, name: string, p: proc(): R) =
  proc wrap(): JsonNode =
    return p().toJson()
  bindProc(w, name, wrap)

proc bindProc*[A1](w: Webview, name: string, p: proc(arg1: A1)) =
  proc wrap(arg1: JsonNode) =
    p(arg1[0].jsonTo(A1))
  bindProc(w, name, wrap)


# proc bindProc*(w: Webview; scope, name: string; p: ProcA1R) =
#   let newName = randomString()
#   echo newName
#   bindProc(w, newName, p)
#   let jsScope = fmt"""
# document.addEventListener("DOMContentLoaded", () => {{
#     // Notify Go that DOM is loaded
#     window.external['invoke']('DOMContentLoaded');
# }});
#     console.log('DOM fully loaded and parsed');
#     if(document.readyState === 'interactive') alert({newName});
#     if (typeof {scope} === "undefined"){{ var {scope} = Object();}}
#       alert("asdasdASssa");
#       {scope}.{name} = {newName};
#       alert("asdasdAS");


#   """
#   echo jsScope
#   w.eval(jsScope)


macro bindProcs*(w: Webview, n: untyped): untyped =
  ## bind procs like:
  ##
  ## .. code-block:: nim
  ## 
  ##    proc fn(arg: JsonNode): JsonNode
  ##    proc fn(arg: JsonNode)
  ##    proc fn(): JsonNode
  ##    proc fn[T, U](arg: T): U
  ##    proc fn[T](arg: T)
  ##    proc fn()
  ##
  ## to webview ``w``
  ## then you can invoke in js side, like this:
  ##
  ## .. code-block:: js
  ## 
  ##    fn(arg)
  ##
  expectKind(n, nnkStmtList)
  let body = n
  for def in n:
    expectKind(def, nnkProcDef)
    let params = def.params()
    let fname = $def[0]
    # expectKind(params[0], nnkSym)
    if params.len() == 1 and params[0].kind() == nnkEmpty: # no args
      body.add(newCall("bindProc", w, newLit(fname), newIdentNode(fname)))
      continue 
    if params.len() > 2 :
      error("""only proc like `proc fn[T, U](arg: T): U` or 
              `proc fn[T](arg: T)` or 
              `proc()`
            is allowed""", 
            def)
    body.add(newCall("bindProc", w, newLit(fname), newIdentNode(fname)))
  result = newBlockStmt(body)
  echo repr result


when isMainModule:
  let w = newWebView(true)
  w.set_title("Minimal example")
  w.set_size(480, 320, WindowSizeHint.None)
  w.navigate("")

  let a = "asdasdasd"
  w.`bind`("test123", proc(seq: cstring, req: cstring, arg: pointer) {.cdecl.} = w.`return`(seq, 0.cint, cstring("{0: \"Success?" & $seq & $req & "\"}")), cast[pointer](a.unsafeAddr))

  proc test(a: JsonNode): JsonNode =
    assert a[0].getStr() != "error"
    %*fmt"This is: {a}"
    
  w.bindProc("test", test)

  proc empty(): JsonNode =
    %*"Success"
  w.bindProc("empty", empty)

  w.bindProcs:
    proc open() = echo "open"
    proc close() = echo "close"
    proc openlose(): JsonNode = %*"openlose"
    proc asd(a: string): string = a & ". why?"

  # w.bindProc("scope", "test", test)
  w.eval("alert(\"asdasdads\")")
  # w.bind("asdasd", nil, nil)
  w.run()



  # test("0").then((aa) => {console.log(aa)})