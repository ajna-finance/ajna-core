#!/usr/bin/env bash

root=$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )
output="$root/mutants"

echo "Starting mutation campaign in $(pwd)"

echo "Mutating Source"

find src \
  -name '*.sol' \
  -not -path '*/interfaces/*' \
  -print0 | while IFS= read -r -d '' file
do
  name="$(basename "$file" .sol)"
  out="$output/src"
  mkdir -p "$out"
  dir="$out/$name"
  raw_log="$out/.$name.raw.log"
  log="$out/$name.log"
  if [[ -f "$log" ]]
  then echo "Skipping $file because $log already exists"
  elif [[ -f "$raw_log" ]]
  then echo "Skipping $file because $raw_log already exists"
  else
    echo "Mutating $file (no file at $log)"
    mkdir -p "$dir"
    mutate "$file" --cmd "timeout 180s make test" --mutantDir "$dir" > "$raw_log"
    echo "Cleaning mutation results at $raw_log"
    head -n 4 "$raw_log" > "$log"
    sed -n '/.*\.\.\.VALID \[written to.*/p' < "$raw_log" >> "$log"
    tail -n 4 "$raw_log" >> "$log"
  fi
  if [[ "$?" != "0" ]]
  then exit
  fi
done

echo "Mutating tests"

find tests \
  -name '*.t.sol' \
  -print0 | while IFS= read -r -d '' file
do
  name="$(basename "$file" .sol)" # preserves the .t. extension prefix
  out="$output/tests"
  mkdir -p "$out"
  log="$out/$name.log" 
  if [[ -f "$log" ]]
  then echo "Skipping $file because $log already exists"
  else
    echo "Mutating $file"
    if [[ -f "./necessist.db" ]]
    then necessist --resume "$file" > "$log"
    else necessist "$file" > "$log"
    fi
    if [[ "$?" != "0" ]]
    then exit # if we get ctrl-c or an error, abort
    fi
  fi
done

