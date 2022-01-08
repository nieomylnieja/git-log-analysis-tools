#!/usr/local/bin/gawk -f

function printJSON() {
  sub(/}$/, "", json)
  printf "%s,\"inserted\":%d,\"deleted\":%d}\n", json, ic, dc
}

function resetVariables() { ic=0; dc=0; json=""; isDiffOutput=0 }

BEGIN                         { resetVariables() }
/^@@.*@@$/                    { isDiffOutput=1 }
/^JSON=/ && !isDiffOutput     { sub(/^JSON=/, "", $0); json=$0 }
/^\*\*\*{{{$/ && NR > 1       { printJSON(); resetVariables() }
/^\+([^\+].*|$)/              { ic++ }
/^\-([^\-].*|$)/              { dc++ }
END                           { printJSON() }

