#!/bin/bash
s=$(brownie compile --size | sed 's/\x1b\[[0-9;]*m//g')  # strip ansi color from brownie output
echo "${s}"
regex='============ Deployment Bytecode Sizes ============\s*(\w+)\s+-\s+([0-9,B]+)\s+\(([0-9.]+%)\)'
[[ "$s" =~ $regex ]]
largest_contract=${BASH_REMATCH[1]}
largest_size=$(echo "${BASH_REMATCH[2]}" | sed -e 's/,//g' -e 's/B//g')
largest_percent=${BASH_REMATCH[3]}

limit=24576
echo "$largest_contract is $largest_size bytes ($largest_percent of $limit byte size limit)."
if (( largest_size > limit)); then
  exit 1
fi;
