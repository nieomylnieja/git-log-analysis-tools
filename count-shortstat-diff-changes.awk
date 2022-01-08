#!/usr/local/bin/gawk -f

function printJSON() {
  sub(/}$/, "", json)
  printf "%s,\"filesChanged\":%d,\"inserted\":%d,\"deleted\":%d}\n", json, fc, ic, dc
}

function resetVariables() { ic=0; dc=0; fc=0; json="" }

function extractNumber(s) { return gensub(/ ([0-9]+) .*/, "\\1", "g", s) }
function doIt() {
  for (i=1; i<=NF; i++) {
    if ($i ~ /files? changed/) fc=extractNumber($i)
    else if ($i ~ /deletions?\(-\)/) dc=extractNumber($i)
    else if ($i ~ /insertions?\(\+\)/) ic=extractNumber($i)
  }
}

BEGIN       { FS=","; resetVariables() }
/^{/        { json=$0 }
/^$/        { printJSON(); resetVariables() }
/^ /        { doIt() }
END         { printJSON() }

