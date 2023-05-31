import re
filename = 'trace.log'

with open(filename, 'r') as f:
   lines = f.readlines()

first_line = lines[0]
full_handler = first_line.split("addr=[")[1].split(']')[0].split(":")[1]
handler_prefix = '_' + ''.join(full_handler[:1].lower())
handler_suffix = full_handler[1:]
test_handler = handler_prefix + handler_suffix

print('function test_regression_failure() external {')
for line in lines:
    function_name = line.split("calldata=")[1].split('(')[0]
    args = line.split("args=")[1].replace("[", "(" ).replace("]", ")" )
    args = re.sub(r"(\s\(\d.*?\))", "", args)
    sequence_call = function_name + args + ";"
    print('    ' + test_handler + '.' + ''.join(sequence_call.splitlines()))
print('}')