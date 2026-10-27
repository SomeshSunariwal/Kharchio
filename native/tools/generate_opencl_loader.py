"""Generate typed optional OpenCL forwards from the pinned Khronos prototypes."""
import pathlib
import re
import sys

header, sources, output = map(pathlib.Path, sys.argv[1:])
used = set()
for source in sources.glob('*.cpp'):
    used.update(re.findall(r'\b(cl[A-Z]\w*)\s*\(', source.read_text(encoding='utf-8')))
text = re.sub(r'/\*.*?\*/', '', header.read_text(encoding='utf-8'), flags=re.S)
prototypes = re.findall(
    r'extern\s+CL_API_ENTRY\s+([^;]+?)\s+CL_API_CALL\s+(cl\w+)\s*\((.*?)\)\s*CL_API_SUFFIX[^;]*;',
    text, flags=re.S)
lines = ['// Generated from pinned Khronos headers; do not edit.',
         '#define CL_TARGET_OPENCL_VERSION 300',
         '#define CL_USE_DEPRECATED_OPENCL_1_2_APIS',
         '#include <CL/cl.h>', '#include <CL/cl_ext.h>', '#include <dlfcn.h>',
         'static void * symbol(const char * name) {',
         '  static void * lib = dlopen("libOpenCL.so", RTLD_NOW | RTLD_LOCAL);',
         '  return lib ? dlsym(lib, name) : nullptr;', '}', 'extern "C" {']
generated = set()
for result, name, parameters in prototypes:
    if name not in used:
        continue
    parts, depth, start = [], 0, 0
    for i, char in enumerate(parameters):
        depth += (char == '(') - (char == ')')
        if char == ',' and depth == 0:
            parts.append(parameters[start:i].strip())
            start = i + 1
    parts.append(parameters[start:].strip())
    names = []
    for part in parts:
        if part in ('void', ''):
            continue
        callback = re.search(r'\*\s*(\w+)\s*\)', part)
        match = callback or re.search(r'(\w+)\s*(?:\[[^]]*\])?$', part)
        if not match:
            raise RuntimeError(f'Cannot parse {name}: {part}')
        names.append(match[1])
    result = ' '.join(result.split())
    lines += [f'{result} CL_API_CALL {name}({parameters}) {{',
              f'  static auto fn = reinterpret_cast<decltype(&::{name})>(symbol("{name}"));',
              '  if (!fn) {']
    if 'errcode_ret' in names:
        lines.append('    if (errcode_ret) *errcode_ret = CL_INVALID_OPERATION;')
    if name == 'clGetPlatformIDs':
        lines += ['    if (num_platforms) *num_platforms = 0;',
                  '    return CL_PLATFORM_NOT_FOUND_KHR;']
    else:
        fallback = 'CL_INVALID_OPERATION' if result == 'cl_int' else 'nullptr'
        lines.append('    return;' if result == 'void' else f'    return {fallback};')
    lines += ['  }', f'  return fn({", ".join(names)});', '}']
    generated.add(name)
if generated != used:
    raise RuntimeError(f'Missing OpenCL prototypes: {used - generated}')
lines.append('}')
output.write_text('\n'.join(lines) + '\n', encoding='utf-8')
