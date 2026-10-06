#!/usr/bin/env python3
"""Validate host-captured Pi v1 JSONL events; do not trust assistant text."""
import json
from pathlib import Path
import stat
import sys

def _arg_path(args):
    if not isinstance(args,dict):
        return None
    p=args.get("path")
    return p if isinstance(p,str) else None

def _workspace_relative(path):
    if not isinstance(path, str) or not path or "\x00" in path or "\\" in path:
        return None
    if path.startswith("/workspace/"):
        path=path[len("/workspace/"):]
    elif path.startswith("/"):
        return None
    parts=path.split("/")
    if ".." in parts:
        return None
    return "/".join(x for x in parts if x not in ("", "."))

def _is_debug_log(path):
    return _workspace_relative(path)=="debug.log"

def _is_math_source(path):
    return _workspace_relative(path)=="src/math.cpp"

def check_trace(path):
    p=Path(path)
    if not stat.S_ISREG(p.lstat().st_mode) or p.stat().st_size>64*1024*1024:
        raise ValueError("ontbrekende/te grote/niet-reguliere Pi-eventlog")
    events=[]
    for line in p.read_text(encoding="utf-8").split("\n"):
        line=line.removesuffix("\r")
        if line.strip():
            value=json.loads(line)
            if not isinstance(value,dict):
                raise ValueError("ongeldige eventvorm")
            events.append(value)
    pending={};seen=set();used=set();completed=[];final_assistant=None;settled=False;ended=False
    for e in events:
        kind=e.get("type")
        if kind=="agent_start": settled=False; ended=False
        elif kind=="tool_execution_start":
            ident,name,args=e.get("toolCallId"),e.get("toolName"),e.get("args")
            if not isinstance(ident,str) or not ident or ident in seen:
                raise ValueError("ontbrekende/gedupliceerde toolCallId")
            if not isinstance(name,str) or not name:
                raise ValueError("ontbrekende toolName")
            if args is not None and not isinstance(args,dict):
                raise ValueError("ongeldige tool args")
            seen.add(ident);pending[ident]=(name,args if isinstance(args,dict) else {})
        elif kind=="tool_execution_end":
            ident,name=e.get("toolCallId"),e.get("toolName")
            if not isinstance(ident,str) or ident not in pending or pending[ident][0]!=name:
                raise ValueError("tool-einde zonder passende start")
            if type(e.get("isError")) is not bool:
                raise ValueError("ontbrekende/ongeldige isError")
            _,args=pending.pop(ident)
            if e["isError"] is False:
                used.add(name);completed.append((name,args))
        elif kind=="message_end":
            message=e.get("message")
            if not isinstance(message,dict): raise ValueError("ongeldig message_end")
            if message.get("role")=="assistant": final_assistant=message
        elif kind=="agent_end":
            if e.get("willRetry") is not False: raise ValueError("agent_end mist definitieve willRetry=false")
            ended=True
        elif kind=="agent_settled": settled=True
    if pending or not ended or not settled:
        raise ValueError("agent niet volledig afgesloten of tools nog pending")
    if not final_assistant or final_assistant.get("stopReason")!="stop":
        raise ValueError("geen normale finale assistant completion")
    if "read" not in used or not used.intersection({"edit","write"}):
        raise ValueError("geen bewezen read + edit/write")
    debug_reads=[_arg_path(a) for n,a in completed if n=="read" and _is_debug_log(_arg_path(a))]
    source_writes=[_arg_path(a) for n,a in completed if n in {"edit","write"} and _is_math_source(_arg_path(a))]
    if not debug_reads: raise ValueError("debug.log is niet aantoonbaar succesvol gelezen")
    if not source_writes: raise ValueError("src/math.cpp is niet aantoonbaar succesvol gewijzigd")
    first_read=next(i for i,(n,a) in enumerate(completed) if n=="read" and _is_debug_log(_arg_path(a)))
    first_write=next(i for i,(n,a) in enumerate(completed) if n in {"edit","write"} and _is_math_source(_arg_path(a)))
    if first_read >= first_write:
        raise ValueError("source gewijzigd voordat debuglog succesvol gelezen was")
    return {"status":"PASS","observed_completed_tools":sorted(used),"debug_log_read_proven":True,"math_source_edit_proven":True,"debug_log_paths":debug_reads,"source_edit_paths":source_writes,"agent_settled":True}

if __name__=="__main__":
    try: print(json.dumps(check_trace(sys.argv[1])))
    except (OSError,ValueError,TypeError,IndexError) as exc: raise SystemExit(f"FAIL: {exc}")
