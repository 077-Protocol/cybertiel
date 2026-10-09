#!/usr/bin/env bash
set -Eeuo pipefail
required=(node npm pi git gcc g++ clang clang-tidy clang-format clangd cmake ninja meson bear cppcheck shellcheck ccache gdb valgrind autoconf automake libtoolize python3 pip3 pytest mypy pwsh x86_64-w64-mingw32-gcc-posix x86_64-w64-mingw32-g++-posix)
for tool in "${required[@]}"; do
    command -v "$tool" >/dev/null || { echo "MISSING:$tool" >&2; exit 31; }
done
smoke_dir=$(mktemp -d /tmp/cybertiel-toolchain.XXXXXXXX)
trap 'rm -rf -- "$smoke_dir"' EXIT
cd "$smoke_dir"
export HOME="$smoke_dir/home"
mkdir -m 0700 "$HOME"
export XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache" XDG_DATA_HOME="$HOME/.local/share"
mkdir -p -m 0700 "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
[[ "$(pwsh --version)" == "PowerShell 7.6.6" ]] || { pwsh --version >&2; exit 32; }

# A real local Git checkpoint, not only `git --version`.
git init -q git-smoke
printf 'checkpoint-smoke\n' > git-smoke/checkpoint.txt
git -C git-smoke add checkpoint.txt
git -C git-smoke commit -qm 'CyberTiel checkpoint smoke'
test -n "$(git -C git-smoke rev-parse HEAD)"

# Python syntax, tests, types and an isolated venv.
printf 'def add(a: int, b: int) -> int:\n    return a + b\n' > calc.py
printf 'from calc import add\ndef test_add():\n    assert add(19, 23) == 42\n' > test_calc.py
python3 -m py_compile calc.py test_calc.py
pytest -q -p no:cacheprovider test_calc.py | grep -Eq '1 passed'
mypy --no-incremental --cache-dir=/tmp/cybertiel-mypy-cache calc.py | grep -Fqx 'Success: no issues found in 1 source file'
python3 -m venv venv
venv/bin/python -m pip --version >/dev/null

# Static-analysis/format/lint tools must process real inputs successfully.
cat > native.c <<'EOF_NATIVE'
int answer(void) {
  return 42;
}
int main(void) {
  return answer() - 42;
}
EOF_NATIVE
# Normalize our generated fixture with the installed formatter first.
clang-format --style=LLVM -i native.c
clang-format --dry-run --Werror native.c
clang-tidy native.c -- -std=c11 >/dev/null
cppcheck --quiet --error-exitcode=35 --enable=warning,style,performance,portability native.c
cat > clean.sh <<'EOF_SH'
#!/bin/sh
set -eu
printf '%s\n' ok
EOF_SH
shellcheck clean.sh

# Compiler sanitizer runtimes must really link and execute in the final sandbox.
gcc -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer native.c -o native-sanitized
ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 ./native-sanitized
cat > native.cpp <<'EOF_CXX'
#include <vector>
int main() {
  std::vector<int> values{19, 23};
  return values.at(0) + values.at(1) == 42 ? 0 : 1;
}
EOF_CXX
g++ -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer native.cpp -o native-cxx-sanitized
ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 ./native-cxx-sanitized

# Valgrind gets a real clean process, not just a version probe.
gcc -O0 -g native.c -o native-valgrind
valgrind --quiet --error-exitcode=36 --leak-check=full ./native-valgrind

# GDB is useful, but Docker's default seccomp/AppArmor may deliberately restrict
# ptrace. Record the target capability without weakening the sandbox or lying.
cat > gdb-target.c <<'EOF_GDB'
int ct_gdb_value = 42;
int main(void) { return ct_gdb_value == 42 ? 0 : 1; }
EOF_GDB
gcc -O0 -g gdb-target.c -o gdb-target
gdb_rc=0
timeout 20s gdb -q -batch -ex 'break main' -ex run -ex 'print ct_gdb_value' ./gdb-target >gdb.out 2>&1 || gdb_rc=$?
python3 /opt/cybertiel/gdb-result-check.py "$gdb_rc" gdb.out

# PowerShell 7 on Linux: parser + runtime. This does not qualify WinPS 5.1.
pwsh -NoLogo -NoProfile -NonInteractive -Command '$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseInput("param([int]`$x) `$x + 1", [ref]$tokens, [ref]$errors) > $null; if ($errors.Count -ne 0) { exit 33 }; if ((2+3) -ne 5) { exit 34 }; Write-Output CT_PWSH_OK' | grep -qx CT_PWSH_OK

printf 'CT_TOOLCHAIN_OK\n'
printf 'node=%s\n' "$(node --version)"
printf 'npm=%s\n' "$(npm --version)"
printf 'pi=%s\n' "$(pi --version)"
printf 'python=%s\n' "$(python3 --version 2>&1)"
printf 'pytest=%s\n' "$(pytest --version | head -n1)"
printf 'mypy=%s\n' "$(mypy --version | head -n1)"
printf 'meson=%s\n' "$(meson --version)"
printf 'valgrind=%s\n' "$(valgrind --version)"
printf 'gdb=%s\n' "$(gdb --version | sed -n '1p')"
printf 'powershell=%s\n' "$(pwsh --version)"
printf 'cppcheck=%s\n' "$(cppcheck --version | sed -n '1p')"
printf 'shellcheck=%s\n' "$(shellcheck --version | awk '/^version:/{print $2}')"
printf 'ccache=%s\n' "$(ccache --version | sed -n '1p')"
