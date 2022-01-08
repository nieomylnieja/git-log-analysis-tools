#!/bin/bash

set -o errtrace
set -eo pipefail

error() {
  printf "ERROR: %s\n" "$@" 1>&2
  exit 1
}

help() {
  cat <<EOF

USAGE:
  $(basename $0) functions [OPTIONS] <PATH>
  $(basename $0) packages [OPTIONS] <PATH>

COMMANDS:
    functions
        Gather all the functions names. Outputs in JSON format.
    packages
        Gather all the package names. Outputs in JSON format.

ARGS:
    <PATH>...
        A directory to search recursively.

OPTIONS:
    -o, --output     File to which to write the results.
    -h, --help       Display this screen.

REQUIREMENTS: ripgrep, jq, parallel. gawk

EOF
}

for dep in rg jq parallel gawk; do
  if ! which $dep >/dev/null; then
    error "Required binary $dep was not found in PATH"
  fi
done

while test $# -gt 0; do
  case "$1" in
    -h|--help)
      help
      exit 0
      ;;
    functions|packages)
      if [[ -n "$COMMAND" ]]; then
        error "you can only use one command"
      fi
      COMMAND="$1"
      shift
      ;;
    -o)
      shift
      if test $# -gt 0; then
        export OUTPUT=$1
      else
        error "no output file specified"
      fi
      shift
      ;;
    --output*)
      OUTPUT=`echo $1 | sed -e 's/^[^=]*=//g'`
      shift
      ;;
    *)
      break
      ;;
  esac
done

if [[ -z "$1" ]]; then
  error "missing <PATH> argument"
fi

REPO="$1"

main() {
  if [ "$COMMAND" = "functions" ]; then
    result=$(gatherFunctions)
  elif [ "$COMMAND" = "packages" ]; then
    result=$(gatherPackages)
  fi

  redirectToConsoleOrFile "$result"
}

gatherPackages() {
  # Exports are required for the gnu-parallel subshell to see these
  export -f gitLogPackages
  export REPO=${REPO}

  rg --type=go --no-line-number --json -- '^package \w+$' ${REPO} | \
  jq 'select(.type == "match").data | 
    {
      "path": (.path.text | ltrimstr("'${REPO}'/")),
      "package": (.submatches[0].match.text | ltrimstr("package "))
    }' | \
  sed -r 's/("path": )(.*)(\/[^\/]+\.go)/\1\2/g' | \
  jq --slurp -c 'unique_by(.path,.package) | .[]' | \
  parallel gitLogPackages {} | \
  jq --slurp
}

gitLogPackages() {
  local path="$(echo "$1" | jq -r .path)"
  git -C ${REPO} log --shortstat \
    --pretty=format:$(echo '
      {
        "hash":"%H",
        "author":{
          "name":"%aN",
          "mail":"%aE"
        },
        "date":"%aI",
        "message":"%f",
        "coAuthors":"%(trailers:key=Co-authored-by,valueonly,separator=::)"
      }' | jq -c ) -- "$path" | \
  ./count-shortstat-diff-changes.awk | \
  jq '
    (.coAuthors |= split("::")) |
    .coAuthors[] |= (split(" <") |
    {"name":.[0],"mail":(.[1] | rtrimstr(">"))})' | \
  jq --slurp "$1 * {\"commits\":.}"
}

gatherFunctions() {
  # Exports are required for the gnu-parallel subshell to see these
  export -f gitLogFunctions
  export REPO=${REPO}

  rg --type go --only-matching --no-line-number --no-heading \
    -e '^func\s*(\([^\)]+\)\s*)?([^\(\s]*)' \
    -r '"func":"$2":"receiver":"$1"' -- ${REPO} | \
  awk -F: '
    {
      gsub("'${REPO}'/", "", $1);
      gsub(/\( *[^\* ]*[ *]*/, "", $5);
      gsub(/[\) ]*/, "", $5);
      printf "{\"path\":\"%s\",%s:%s,%s:%s}\n", $1, $2, $3, $4, $5
    }' | \
  parallel gitLogFunctions {} | \
  jq --slurp
}

gitLogFunctions() {
  read -r -d '\n' path func <<<"$(echo "$1" | jq -r '.path, .func')"
  git -C ${REPO} log \
    -L ":$func:$path" \
    --pretty=format:'***{{{%n%nJSON='$(echo '
      {
        "hash":"%H",
        "author":{
          "name":"%aN",
          "mail":"%aE"
        },
        "date":"%aI",
        "message":"%f",
        "coAuthors":"%(trailers:key=Co-authored-by,valueonly,separator=::)"
      }' | jq -c) | \
  ./count-functions-diff-changes.awk | \
  jq '
    (.coAuthors |= split("::")) |
    .coAuthors[] |= (split(" <") |
    {"name":.[0],"mail":(.[1] | rtrimstr(">"))})' | \
  jq --slurp "$1 * {\"commits\":.}"
}

redirectToConsoleOrFile() {
  if [[ -z "$OUTPUT" ]]; then
    jq <<<"$@"
  else
    echo "$@" > "$OUTPUT"
  fi
}

main "$@"
