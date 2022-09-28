#!/bin/bash
s=$(brownie compile --size)
echo "${s}"
regex='============ Deployment Bytecode Sizes ============\s*(\w+)\s+-\s+([0-9,B]+)\s+\('
[[ "$s" =~ $regex ]]
largest_contract=${BASH_REMATCH[1]}
largest_size=$(echo "${BASH_REMATCH[2]}" | sed -e 's/,//g' -e 's/B//g')

limit=24576
exitcode=0
message=    # to make shellcheck happy
if (( largest_size > limit)); then
  message="$largest_contract is $largest_size bytes, over size limit of $limit bytes."
  exitcode=1
else
  message="$largest_contract is $largest_size bytes, under size limit of $limit bytes."
fi;

echo "$message"
exit $exitcode