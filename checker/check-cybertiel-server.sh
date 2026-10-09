#!/usr/bin/env bash
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
unset PYTHONPATH PYTHONHOME PYTHONSTARTUP BASH_ENV ENV
[[ -x /usr/bin/python3 ]] || { echo 'Python3 ontbreekt. Geen wijzigingen uitgevoerd.' >&2; exit 2; }
exec /usr/bin/python3 -I - "$@" <<'CYBERTIEL_DIAGNOSTIC_PY'
#!/usr/bin/env python3
"""CyberTiel diagnostic, CT-CHECK-2. Read-only by default, apart from its reports.
No source/eval of installed scripts; no package install/update/download; no secrets
or project/log contents in output. Optional runtime probes create tightly bounded,
temporary Docker containers and synthetic files only, never run the user project.
Not an adversarial attestation against root/Docker-admin or a compromised kernel.
"""
from __future__ import annotations
import argparse, collections, datetime, errno, fcntl, hashlib, json, math, os
from pathlib import Path
import platform, re, selectors, shutil, signal, stat, subprocess, sys, tempfile, time

VERSION = 'CT-CHECK-2.9.6'
RESEARCH_DATE = '2026-10-06'
# Independent v16+ history plus current v25 baseline from frozen generated files.
BASELINES = {'2026-10-05.v16': {'installer_sha256': 'a52df473021e1e5d1b3b4dcb60af42b9218fd28789b4f172e1276d2b8402411a', 'llama_commit': '7fe450e19305b828c199d602c23a8337aaa1f03b', 'managed_files': {'/opt/cybertiel/bundle/Dockerfile.agent': 'c08cc65b87521e586f41124bcc103f6b3a1b6c849b590ce928d87b1550399fe4', '/opt/cybertiel/bundle/Dockerfile.llama': '1a1d5252390ec21ca20113a5c74de0a68fbdb969a9d0fb1e15abaf34166adfc0', '/opt/cybertiel/bundle/accept.cpp': 'c84ca491a847683d6b618701f0cc8dbc01f28d6429101b2ca7b421504ee3eb69', '/opt/cybertiel/bundle/agent-entrypoint.py': '3211f5985e39d11ce4c15e673243ea2ee0058d7488f99e07a876ba22e308c56e', '/opt/cybertiel/bundle/agent-policy.md': '7fbe4aee21613ebe7b6403ea9ceffbb60c63c74c59817afc562e9b4dba6e10d1', '/opt/cybertiel/bundle/bash-timeout.ts': '068df4aae6b0405e53eb7455f4b51722f4c1574ad0d413224c1184666e80be81', '/opt/cybertiel/bundle/check-ready.py': 'd9c3e30374e448d465380ec4f7741e60a6227f632e91d215fb833e4dfada8e72', '/opt/cybertiel/bundle/cybertiel-launcher': 'ec677c354b3a84c74293eeacd9246f6ae5234af35a623092ace2e815885b4820', '/opt/cybertiel/bundle/gdb-result-check.py': '66429f53a05bcc4226a24e74b54ffca6e2e538dc06117087b1d66e557e697d47', '/opt/cybertiel/bundle/import-debug-log.py': 'e5352c4c5393450efa685314f85e4b739dae38ffc2178c024eb055111c2bc1e0', '/opt/cybertiel/bundle/mingw-x64.cmake': '3841d3cebcc32a9107c033b4f3434edd6a4b4bfcd4840194452fc42939b5c114', '/opt/cybertiel/bundle/models.json': '647f53375a797744906f4b05718adc3a94eecf5503b238cdede073c2196c1dac', '/opt/cybertiel/bundle/pi-settings-check.mjs': '4c22b5d390e7929db10afc32d2df7fb1667e5b7bf2485540d4f1ca9a8dbdcdf0', '/opt/cybertiel/bundle/settings.json': 'ebb42a9b10b0a1632c95c2b8599aef192c3e9d9f7e03756558d177de1489f3f3', '/opt/cybertiel/bundle/toolchain-smoke.sh': 'a01bdd11f9378fd5ea34cb3e0b64a11ecb85b35a838049f4e2eabce01897e735', '/opt/cybertiel/bundle/trace-check.py': '69fd22c8431d16f6c91b1ce99ca683eb67c8b0b5961182e9b4f7c8bf92cd6afe', '/opt/cybertiel/bundle/verify-agent.py': '6739fefa9015bd8c08b0c3f3b82b11dc2af94334e61f1d3ebc40cc069b7620e4', '/opt/cybertiel/bundle/verify-pi-lock.py': '520f492fb1fe826fa48b1cd3f9574f880202bdce785947a40a71726a678469a9', '/usr/local/bin/cybertiel': 'ec677c354b3a84c74293eeacd9246f6ae5234af35a623092ace2e815885b4820'}, 'models': {'Cyber-Tiel-Coder-35B-A3B-UD-Q8_K_XL.gguf': '7509f8c8e3b2df4c7bc5966fa711478c12c2c424f2832f7933f1e46dd180feb2', 'mmproj-BF16.gguf': 'd9ce31026d1cb1f3f8d5152e2e2a014d9d2b302b6c93a7dc07bb0a0487f52837'}, 'models.json': {'providers': {'cybertiel-local': {'api': 'openai-completions', 'apiKey': '@LOCAL_KEY@', 'baseUrl': 'http://cybertiel-model:8080/v1', 'models': [{'compat': {'maxTokensField': 'max_tokens', 'supportsDeveloperRole': False, 'supportsReasoningEffort': False, 'supportsStore': False}, 'contextWindow': 262144, 'cost': {'cacheRead': 0, 'cacheWrite': 0, 'input': 0, 'output': 0}, 'id': 'cybertiel-35b', 'input': ['text', 'image'], 'maxTokens': 258048, 'name': 'CyberTiel 35B-A3B official UD-Q8_K_XL (not BF16)', 'reasoning': True, 'samplingParams': {'min_p': 0, 'temperature': 0.6, 'top_k': 20, 'top_p': 0.95}}]}}}, 'settings.json': {'cacheWarming': 'off', 'compaction': {'enabled': True, 'keepRecentTokens': 16000, 'reserveTokens': 32768}, 'defaultModel': 'cybertiel-35b', 'defaultProjectTrust': 'never', 'defaultProvider': 'cybertiel-local', 'defaultThinkingLevel': 'high', 'defaultTools': ['read', 'bash', 'edit', 'write', 'grep', 'find', 'ls'], 'enableAnalytics': False, 'enableInstallTelemetry': False, 'httpIdleTimeoutMs': 7200000, 'retry': {'provider': {'timeoutMs': 7200000}}}}, '2026-10-05.v17': {'brace_version': '5.0.12', 'installer_sha256': '74017c97dc3aac74649d8d9305e811f60865e1221cfb24b6bf051b775b314f30', 'llama_commit': '7fe450e19305b828c199d602c23a8337aaa1f03b', 'managed_files': {'/opt/cybertiel/bundle/Dockerfile.agent': '0cebad8498e9b4adb2708bb0ae4f55f011a12940257194a0ff6ce49e68190735', '/opt/cybertiel/bundle/Dockerfile.llama': '1a1d5252390ec21ca20113a5c74de0a68fbdb969a9d0fb1e15abaf34166adfc0', '/opt/cybertiel/bundle/accept.cpp': 'c84ca491a847683d6b618701f0cc8dbc01f28d6429101b2ca7b421504ee3eb69', '/opt/cybertiel/bundle/agent-entrypoint.py': 'bdad280173d77fdafa6b8d0980627feef84c8a8e207c6c38625cf7af8b6ac9f7', '/opt/cybertiel/bundle/agent-policy.md': 'ee5f541ec96fefbc2c2d6eac96a9f7e5bdb81008c876bc590f3135758eed04be', '/opt/cybertiel/bundle/bash-timeout.ts': '068df4aae6b0405e53eb7455f4b51722f4c1574ad0d413224c1184666e80be81', '/opt/cybertiel/bundle/check-ready.py': 'd9c3e30374e448d465380ec4f7741e60a6227f632e91d215fb833e4dfada8e72', '/opt/cybertiel/bundle/cybertiel-launcher': '70aff6ae1fec02a7663076505a139af12841c33b75d26af7d66e4c2c4cea2c49', '/opt/cybertiel/bundle/gdb-result-check.py': '66429f53a05bcc4226a24e74b54ffca6e2e538dc06117087b1d66e557e697d47', '/opt/cybertiel/bundle/import-debug-log.py': 'e5352c4c5393450efa685314f85e4b739dae38ffc2178c024eb055111c2bc1e0', '/opt/cybertiel/bundle/mingw-x64.cmake': '3841d3cebcc32a9107c033b4f3434edd6a4b4bfcd4840194452fc42939b5c114', '/opt/cybertiel/bundle/models.json': '647f53375a797744906f4b05718adc3a94eecf5503b238cdede073c2196c1dac', '/opt/cybertiel/bundle/pi-settings-check.mjs': '4c22b5d390e7929db10afc32d2df7fb1667e5b7bf2485540d4f1ca9a8dbdcdf0', '/opt/cybertiel/bundle/settings.json': 'ebb42a9b10b0a1632c95c2b8599aef192c3e9d9f7e03756558d177de1489f3f3', '/opt/cybertiel/bundle/toolchain-smoke.sh': 'a01bdd11f9378fd5ea34cb3e0b64a11ecb85b35a838049f4e2eabce01897e735', '/opt/cybertiel/bundle/trace-check.py': '69fd22c8431d16f6c91b1ce99ca683eb67c8b0b5961182e9b4f7c8bf92cd6afe', '/opt/cybertiel/bundle/verify-agent.py': '6739fefa9015bd8c08b0c3f3b82b11dc2af94334e61f1d3ebc40cc069b7620e4', '/opt/cybertiel/bundle/verify-pi-lock.py': 'ad9515ac567d5867eba7a78d5cffa25de9dd0fdbb01a50536e09158057813e79', '/usr/local/bin/cybertiel': '70aff6ae1fec02a7663076505a139af12841c33b75d26af7d66e4c2c4cea2c49'}, 'models': {'Cyber-Tiel-Coder-35B-A3B-UD-Q8_K_XL.gguf': '7509f8c8e3b2df4c7bc5966fa711478c12c2c424f2832f7933f1e46dd180feb2', 'mmproj-BF16.gguf': 'd9ce31026d1cb1f3f8d5152e2e2a014d9d2b302b6c93a7dc07bb0a0487f52837'}, 'models.json': {'providers': {'cybertiel-local': {'api': 'openai-completions', 'apiKey': '@LOCAL_KEY@', 'baseUrl': 'http://cybertiel-model:8080/v1', 'models': [{'compat': {'maxTokensField': 'max_tokens', 'supportsDeveloperRole': False, 'supportsReasoningEffort': False, 'supportsStore': False}, 'contextWindow': 262144, 'cost': {'cacheRead': 0, 'cacheWrite': 0, 'input': 0, 'output': 0}, 'id': 'cybertiel-35b', 'input': ['text', 'image'], 'maxTokens': 258048, 'name': 'CyberTiel 35B-A3B official UD-Q8_K_XL (not BF16)', 'reasoning': True, 'samplingParams': {'min_p': 0, 'temperature': 0.6, 'top_k': 20, 'top_p': 0.95}}]}}}, 'pi_lock_sha256': 'd2a441d6f2f137a0a7fe2687cda0350e2028e49724776574db337674d2097fe7', 'pi_package_sha256': '9cae3572dc8090c7fd3ff7c7662ec7bba1b95529126e2054d6b42220be3b2fea', 'pi_version': '1.0.3', 'settings.json': {'cacheWarming': 'off', 'compaction': {'enabled': True, 'keepRecentTokens': 16000, 'reserveTokens': 32768}, 'defaultModel': 'cybertiel-35b', 'defaultProjectTrust': 'never', 'defaultProvider': 'cybertiel-local', 'defaultThinkingLevel': 'high', 'defaultTools': ['read', 'bash', 'edit', 'write', 'grep', 'find', 'ls'], 'enableAnalytics': False, 'enableInstallTelemetry': False, 'httpIdleTimeoutMs': 7200000, 'retry': {'provider': {'timeoutMs': 7200000}}}}, '2026-10-06.v18': {'brace_version': '5.0.12', 'installer_sha256': '88dff3e7b1c6de5bce0f5d136f8a2f7a225325fe5ae34521941cfe29e6611468', 'llama_commit': '7fe450e19305b828c199d602c23a8337aaa1f03b', 'managed_files': {'/opt/cybertiel/bundle/Dockerfile.agent': '0cebad8498e9b4adb2708bb0ae4f55f011a12940257194a0ff6ce49e68190735', '/opt/cybertiel/bundle/Dockerfile.llama': '1a1d5252390ec21ca20113a5c74de0a68fbdb969a9d0fb1e15abaf34166adfc0', '/opt/cybertiel/bundle/accept.cpp': 'c84ca491a847683d6b618701f0cc8dbc01f28d6429101b2ca7b421504ee3eb69', '/opt/cybertiel/bundle/agent-entrypoint.py': 'bdad280173d77fdafa6b8d0980627feef84c8a8e207c6c38625cf7af8b6ac9f7', '/opt/cybertiel/bundle/agent-policy.md': 'ee5f541ec96fefbc2c2d6eac96a9f7e5bdb81008c876bc590f3135758eed04be', '/opt/cybertiel/bundle/bash-timeout.ts': '068df4aae6b0405e53eb7455f4b51722f4c1574ad0d413224c1184666e80be81', '/opt/cybertiel/bundle/check-ready.py': 'd9c3e30374e448d465380ec4f7741e60a6227f632e91d215fb833e4dfada8e72', '/opt/cybertiel/bundle/cybertiel-launcher': '8c0250f200112c58be4d72d87c70f73dcef4fd24c2d0314f65e281e314540287', '/opt/cybertiel/bundle/gdb-result-check.py': '66429f53a05bcc4226a24e74b54ffca6e2e538dc06117087b1d66e557e697d47', '/opt/cybertiel/bundle/import-debug-log.py': 'e5352c4c5393450efa685314f85e4b739dae38ffc2178c024eb055111c2bc1e0', '/opt/cybertiel/bundle/mingw-x64.cmake': '3841d3cebcc32a9107c033b4f3434edd6a4b4bfcd4840194452fc42939b5c114', '/opt/cybertiel/bundle/models.json': '647f53375a797744906f4b05718adc3a94eecf5503b238cdede073c2196c1dac', '/opt/cybertiel/bundle/pi-settings-check.mjs': '4c22b5d390e7929db10afc32d2df7fb1667e5b7bf2485540d4f1ca9a8dbdcdf0', '/opt/cybertiel/bundle/settings.json': 'ebb42a9b10b0a1632c95c2b8599aef192c3e9d9f7e03756558d177de1489f3f3', '/opt/cybertiel/bundle/toolchain-smoke.sh': 'a01bdd11f9378fd5ea34cb3e0b64a11ecb85b35a838049f4e2eabce01897e735', '/opt/cybertiel/bundle/trace-check.py': '69fd22c8431d16f6c91b1ce99ca683eb67c8b0b5961182e9b4f7c8bf92cd6afe', '/opt/cybertiel/bundle/verify-agent.py': '6739fefa9015bd8c08b0c3f3b82b11dc2af94334e61f1d3ebc40cc069b7620e4', '/opt/cybertiel/bundle/verify-pi-lock.py': 'ad9515ac567d5867eba7a78d5cffa25de9dd0fdbb01a50536e09158057813e79', '/usr/local/bin/cybertiel': '8c0250f200112c58be4d72d87c70f73dcef4fd24c2d0314f65e281e314540287'}, 'models': {'Cyber-Tiel-Coder-35B-A3B-UD-Q8_K_XL.gguf': '7509f8c8e3b2df4c7bc5966fa711478c12c2c424f2832f7933f1e46dd180feb2', 'mmproj-BF16.gguf': 'd9ce31026d1cb1f3f8d5152e2e2a014d9d2b302b6c93a7dc07bb0a0487f52837'}, 'models.json': {'providers': {'cybertiel-local': {'api': 'openai-completions', 'apiKey': '@LOCAL_KEY@', 'baseUrl': 'http://cybertiel-model:8080/v1', 'models': [{'compat': {'maxTokensField': 'max_tokens', 'supportsDeveloperRole': False, 'supportsReasoningEffort': False, 'supportsStore': False}, 'contextWindow': 262144, 'cost': {'cacheRead': 0, 'cacheWrite': 0, 'input': 0, 'output': 0}, 'id': 'cybertiel-35b', 'input': ['text', 'image'], 'maxTokens': 258048, 'name': 'CyberTiel 35B-A3B official UD-Q8_K_XL (not BF16)', 'reasoning': True, 'samplingParams': {'min_p': 0, 'temperature': 0.6, 'top_k': 20, 'top_p': 0.95}}]}}}, 'pi_lock_sha256': 'd2a441d6f2f137a0a7fe2687cda0350e2028e49724776574db337674d2097fe7', 'pi_package_sha256': '9cae3572dc8090c7fd3ff7c7662ec7bba1b95529126e2054d6b42220be3b2fea', 'pi_version': '1.0.3', 'settings.json': {'cacheWarming': 'off', 'compaction': {'enabled': True, 'keepRecentTokens': 16000, 'reserveTokens': 32768}, 'defaultModel': 'cybertiel-35b', 'defaultProjectTrust': 'never', 'defaultProvider': 'cybertiel-local', 'defaultThinkingLevel': 'high', 'defaultTools': ['read', 'bash', 'edit', 'write', 'grep', 'find', 'ls'], 'enableAnalytics': False, 'enableInstallTelemetry': False, 'httpIdleTimeoutMs': 7200000, 'retry': {'provider': {'timeoutMs': 7200000}}}}, '2026-10-06.v19': {'brace_version': '5.0.12', 'installer_sha256': 'ba8bbb93878a2759ac6c34675b8b8d4ba08936fe6c7d1a73c859973e129190c8', 'llama_commit': '7fe450e19305b828c199d602c23a8337aaa1f03b', 'managed_files': {'/opt/cybertiel/bundle/Dockerfile.agent': '0cebad8498e9b4adb2708bb0ae4f55f011a12940257194a0ff6ce49e68190735', '/opt/cybertiel/bundle/Dockerfile.llama': '1a1d5252390ec21ca20113a5c74de0a68fbdb969a9d0fb1e15abaf34166adfc0', '/opt/cybertiel/bundle/accept.cpp': 'c84ca491a847683d6b618701f0cc8dbc01f28d6429101b2ca7b421504ee3eb69', '/opt/cybertiel/bundle/agent-entrypoint.py': 'bdad280173d77fdafa6b8d0980627feef84c8a8e207c6c38625cf7af8b6ac9f7', '/opt/cybertiel/bundle/agent-policy.md': 'ee5f541ec96fefbc2c2d6eac96a9f7e5bdb81008c876bc590f3135758eed04be', '/opt/cybertiel/bundle/bash-timeout.ts': '068df4aae6b0405e53eb7455f4b51722f4c1574ad0d413224c1184666e80be81', '/opt/cybertiel/bundle/check-ready.py': 'd9c3e30374e448d465380ec4f7741e60a6227f632e91d215fb833e4dfada8e72', '/opt/cybertiel/bundle/cybertiel-launcher': '5cb8d2950b48253a8f3ace9b51c7eb1283899ee2db366e9e39e9b0203d934e1a', '/opt/cybertiel/bundle/gdb-result-check.py': '66429f53a05bcc4226a24e74b54ffca6e2e538dc06117087b1d66e557e697d47', '/opt/cybertiel/bundle/import-debug-log.py': 'e5352c4c5393450efa685314f85e4b739dae38ffc2178c024eb055111c2bc1e0', '/opt/cybertiel/bundle/mingw-x64.cmake': '3841d3cebcc32a9107c033b4f3434edd6a4b4bfcd4840194452fc42939b5c114', '/opt/cybertiel/bundle/models.json': '647f53375a797744906f4b05718adc3a94eecf5503b238cdede073c2196c1dac', '/opt/cybertiel/bundle/pi-settings-check.mjs': '4c22b5d390e7929db10afc32d2df7fb1667e5b7bf2485540d4f1ca9a8dbdcdf0', '/opt/cybertiel/bundle/settings.json': 'ebb42a9b10b0a1632c95c2b8599aef192c3e9d9f7e03756558d177de1489f3f3', '/opt/cybertiel/bundle/toolchain-smoke.sh': 'a01bdd11f9378fd5ea34cb3e0b64a11ecb85b35a838049f4e2eabce01897e735', '/opt/cybertiel/bundle/trace-check.py': '69fd22c8431d16f6c91b1ce99ca683eb67c8b0b5961182e9b4f7c8bf92cd6afe', '/opt/cybertiel/bundle/verify-agent.py': '6739fefa9015bd8c08b0c3f3b82b11dc2af94334e61f1d3ebc40cc069b7620e4', '/opt/cybertiel/bundle/verify-pi-lock.py': 'ad9515ac567d5867eba7a78d5cffa25de9dd0fdbb01a50536e09158057813e79', '/usr/local/bin/cybertiel': '5cb8d2950b48253a8f3ace9b51c7eb1283899ee2db366e9e39e9b0203d934e1a'}, 'models': {'Cyber-Tiel-Coder-35B-A3B-UD-Q8_K_XL.gguf': '7509f8c8e3b2df4c7bc5966fa711478c12c2c424f2832f7933f1e46dd180feb2', 'mmproj-BF16.gguf': 'd9ce31026d1cb1f3f8d5152e2e2a014d9d2b302b6c93a7dc07bb0a0487f52837'}, 'models.json': {'providers': {'cybertiel-local': {'api': 'openai-completions', 'apiKey': '@LOCAL_KEY@', 'baseUrl': 'http://cybertiel-model:8080/v1', 'models': [{'compat': {'maxTokensField': 'max_tokens', 'supportsDeveloperRole': False, 'supportsReasoningEffort': False, 'supportsStore': False}, 'contextWindow': 262144, 'cost': {'cacheRead': 0, 'cacheWrite': 0, 'input': 0, 'output': 0}, 'id': 'cybertiel-35b', 'input': ['text', 'image'], 'maxTokens': 258048, 'name': 'CyberTiel 35B-A3B official UD-Q8_K_XL (not BF16)', 'reasoning': True, 'samplingParams': {'min_p': 0, 'temperature': 0.6, 'top_k': 20, 'top_p': 0.95}}]}}}, 'pi_lock_sha256': 'd2a441d6f2f137a0a7fe2687cda0350e2028e49724776574db337674d2097fe7', 'pi_package_sha256': '9cae3572dc8090c7fd3ff7c7662ec7bba1b95529126e2054d6b42220be3b2fea', 'pi_version': '1.0.3', 'settings.json': {'cacheWarming': 'off', 'compaction': {'enabled': True, 'keepRecentTokens': 16000, 'reserveTokens': 32768}, 'defaultModel': 'cybertiel-35b', 'defaultProjectTrust': 'never', 'defaultProvider': 'cybertiel-local', 'defaultThinkingLevel': 'high', 'defaultTools': ['read', 'bash', 'edit', 'write', 'grep', 'find', 'ls'], 'enableAnalytics': False, 'enableInstallTelemetry': False, 'httpIdleTimeoutMs': 7200000, 'retry': {'provider': {'timeoutMs': 7200000}}}}, '2026-10-06.v20': {'brace_version': '5.0.12', 'installer_sha256': 'e17868692f4130f4f908f7e60a920bff375237c3639d226aeb26c37a33cb3743', 'llama_commit': '7fe450e19305b828c199d602c23a8337aaa1f03b', 'managed_files': {'/opt/cybertiel/bundle/Dockerfile.agent': '0cebad8498e9b4adb2708bb0ae4f55f011a12940257194a0ff6ce49e68190735', '/opt/cybertiel/bundle/Dockerfile.llama': '1a1d5252390ec21ca20113a5c74de0a68fbdb969a9d0fb1e15abaf34166adfc0', '/opt/cybertiel/bundle/accept.cpp': 'c84ca491a847683d6b618701f0cc8dbc01f28d6429101b2ca7b421504ee3eb69', '/opt/cybertiel/bundle/agent-entrypoint.py': 'bdad280173d77fdafa6b8d0980627feef84c8a8e207c6c38625cf7af8b6ac9f7', '/opt/cybertiel/bundle/agent-policy.md': 'ee5f541ec96fefbc2c2d6eac96a9f7e5bdb81008c876bc590f3135758eed04be', '/opt/cybertiel/bundle/bash-timeout.ts': '068df4aae6b0405e53eb7455f4b51722f4c1574ad0d413224c1184666e80be81', '/opt/cybertiel/bundle/check-ready.py': 'd9c3e30374e448d465380ec4f7741e60a6227f632e91d215fb833e4dfada8e72', '/opt/cybertiel/bundle/cybertiel-launcher': '07673a36e9f451874a9dfe235ca9104c16ef8e780a3d3eea490e23c0bc259799', '/opt/cybertiel/bundle/gdb-result-check.py': '66429f53a05bcc4226a24e74b54ffca6e2e538dc06117087b1d66e557e697d47', '/opt/cybertiel/bundle/import-debug-log.py': '65919aac7a4f52e7d2c1bb48954abc83bb69d582c460dd081821597a8e61ec6a', '/opt/cybertiel/bundle/mingw-x64.cmake': '3841d3cebcc32a9107c033b4f3434edd6a4b4bfcd4840194452fc42939b5c114', '/opt/cybertiel/bundle/models.json': '647f53375a797744906f4b05718adc3a94eecf5503b238cdede073c2196c1dac', '/opt/cybertiel/bundle/pi-settings-check.mjs': '4c22b5d390e7929db10afc32d2df7fb1667e5b7bf2485540d4f1ca9a8dbdcdf0', '/opt/cybertiel/bundle/settings.json': 'ebb42a9b10b0a1632c95c2b8599aef192c3e9d9f7e03756558d177de1489f3f3', '/opt/cybertiel/bundle/toolchain-smoke.sh': 'a01bdd11f9378fd5ea34cb3e0b64a11ecb85b35a838049f4e2eabce01897e735', '/opt/cybertiel/bundle/trace-check.py': '69fd22c8431d16f6c91b1ce99ca683eb67c8b0b5961182e9b4f7c8bf92cd6afe', '/opt/cybertiel/bundle/verify-agent.py': '6739fefa9015bd8c08b0c3f3b82b11dc2af94334e61f1d3ebc40cc069b7620e4', '/opt/cybertiel/bundle/verify-pi-lock.py': 'ad9515ac567d5867eba7a78d5cffa25de9dd0fdbb01a50536e09158057813e79', '/usr/local/bin/cybertiel': '07673a36e9f451874a9dfe235ca9104c16ef8e780a3d3eea490e23c0bc259799'}, 'models': {'Cyber-Tiel-Coder-35B-A3B-UD-Q8_K_XL.gguf': '7509f8c8e3b2df4c7bc5966fa711478c12c2c424f2832f7933f1e46dd180feb2', 'mmproj-BF16.gguf': 'd9ce31026d1cb1f3f8d5152e2e2a014d9d2b302b6c93a7dc07bb0a0487f52837'}, 'models.json': {'providers': {'cybertiel-local': {'api': 'openai-completions', 'apiKey': '@LOCAL_KEY@', 'baseUrl': 'http://cybertiel-model:8080/v1', 'models': [{'compat': {'maxTokensField': 'max_tokens', 'supportsDeveloperRole': False, 'supportsReasoningEffort': False, 'supportsStore': False}, 'contextWindow': 262144, 'cost': {'cacheRead': 0, 'cacheWrite': 0, 'input': 0, 'output': 0}, 'id': 'cybertiel-35b', 'input': ['text', 'image'], 'maxTokens': 258048, 'name': 'CyberTiel 35B-A3B official UD-Q8_K_XL (not BF16)', 'reasoning': True, 'samplingParams': {'min_p': 0, 'temperature': 0.6, 'top_k': 20, 'top_p': 0.95}}]}}}, 'pi_lock_sha256': 'd2a441d6f2f137a0a7fe2687cda0350e2028e49724776574db337674d2097fe7', 'pi_package_sha256': '9cae3572dc8090c7fd3ff7c7662ec7bba1b95529126e2054d6b42220be3b2fea', 'pi_version': '1.0.3', 'settings.json': {'cacheWarming': 'off', 'compaction': {'enabled': True, 'keepRecentTokens': 16000, 'reserveTokens': 32768}, 'defaultModel': 'cybertiel-35b', 'defaultProjectTrust': 'never', 'defaultProvider': 'cybertiel-local', 'defaultThinkingLevel': 'high', 'defaultTools': ['read', 'bash', 'edit', 'write', 'grep', 'find', 'ls'], 'enableAnalytics': False, 'enableInstallTelemetry': False, 'httpIdleTimeoutMs': 7200000, 'retry': {'provider': {'timeoutMs': 7200000}}}}, '2026-10-06.v21': {'brace_version': '5.0.12', 'installer_sha256': '15bb9d5a065908c26980f66543889cee5ba729172f5161d75ef6537c3fedd085', 'llama_commit': '7fe450e19305b828c199d602c23a8337aaa1f03b', 'managed_files': {'/opt/cybertiel/bundle/Dockerfile.agent': '0cebad8498e9b4adb2708bb0ae4f55f011a12940257194a0ff6ce49e68190735', '/opt/cybertiel/bundle/Dockerfile.llama': '1a1d5252390ec21ca20113a5c74de0a68fbdb969a9d0fb1e15abaf34166adfc0', '/opt/cybertiel/bundle/accept.cpp': 'c84ca491a847683d6b618701f0cc8dbc01f28d6429101b2ca7b421504ee3eb69', '/opt/cybertiel/bundle/agent-entrypoint.py': 'bdad280173d77fdafa6b8d0980627feef84c8a8e207c6c38625cf7af8b6ac9f7', '/opt/cybertiel/bundle/agent-policy.md': 'ee5f541ec96fefbc2c2d6eac96a9f7e5bdb81008c876bc590f3135758eed04be', '/opt/cybertiel/bundle/bash-timeout.ts': '068df4aae6b0405e53eb7455f4b51722f4c1574ad0d413224c1184666e80be81', '/opt/cybertiel/bundle/check-ready.py': 'd9c3e30374e448d465380ec4f7741e60a6227f632e91d215fb833e4dfada8e72', '/opt/cybertiel/bundle/cybertiel-launcher': '8a3c378eb1c7dddda9561a635d5dbd2c9abcac5355e36473def2caa9a6948bd8', '/opt/cybertiel/bundle/gdb-result-check.py': '66429f53a05bcc4226a24e74b54ffca6e2e538dc06117087b1d66e557e697d47', '/opt/cybertiel/bundle/import-debug-log.py': '65919aac7a4f52e7d2c1bb48954abc83bb69d582c460dd081821597a8e61ec6a', '/opt/cybertiel/bundle/mingw-x64.cmake': '3841d3cebcc32a9107c033b4f3434edd6a4b4bfcd4840194452fc42939b5c114', '/opt/cybertiel/bundle/models.json': '647f53375a797744906f4b05718adc3a94eecf5503b238cdede073c2196c1dac', '/opt/cybertiel/bundle/pi-settings-check.mjs': '4c22b5d390e7929db10afc32d2df7fb1667e5b7bf2485540d4f1ca9a8dbdcdf0', '/opt/cybertiel/bundle/settings.json': 'ebb42a9b10b0a1632c95c2b8599aef192c3e9d9f7e03756558d177de1489f3f3', '/opt/cybertiel/bundle/toolchain-smoke.sh': 'a01bdd11f9378fd5ea34cb3e0b64a11ecb85b35a838049f4e2eabce01897e735', '/opt/cybertiel/bundle/trace-check.py': '69fd22c8431d16f6c91b1ce99ca683eb67c8b0b5961182e9b4f7c8bf92cd6afe', '/opt/cybertiel/bundle/verify-agent.py': '6739fefa9015bd8c08b0c3f3b82b11dc2af94334e61f1d3ebc40cc069b7620e4', '/opt/cybertiel/bundle/verify-pi-lock.py': 'ad9515ac567d5867eba7a78d5cffa25de9dd0fdbb01a50536e09158057813e79', '/usr/local/bin/cybertiel': '8a3c378eb1c7dddda9561a635d5dbd2c9abcac5355e36473def2caa9a6948bd8'}, 'models': {'Cyber-Tiel-Coder-35B-A3B-UD-Q8_K_XL.gguf': '7509f8c8e3b2df4c7bc5966fa711478c12c2c424f2832f7933f1e46dd180feb2', 'mmproj-BF16.gguf': 'd9ce31026d1cb1f3f8d5152e2e2a014d9d2b302b6c93a7dc07bb0a0487f52837'}, 'models.json': {'providers': {'cybertiel-local': {'api': 'openai-completions', 'apiKey': '@LOCAL_KEY@', 'baseUrl': 'http://cybertiel-model:8080/v1', 'models': [{'compat': {'maxTokensField': 'max_tokens', 'supportsDeveloperRole': False, 'supportsReasoningEffort': False, 'supportsStore': False}, 'contextWindow': 262144, 'cost': {'cacheRead': 0, 'cacheWrite': 0, 'input': 0, 'output': 0}, 'id': 'cybertiel-35b', 'input': ['text', 'image'], 'maxTokens': 258048, 'name': 'CyberTiel 35B-A3B official UD-Q8_K_XL (not BF16)', 'reasoning': True, 'samplingParams': {'min_p': 0, 'temperature': 0.6, 'top_k': 20, 'top_p': 0.95}}]}}}, 'pi_lock_sha256': 'd2a441d6f2f137a0a7fe2687cda0350e2028e49724776574db337674d2097fe7', 'pi_package_sha256': '9cae3572dc8090c7fd3ff7c7662ec7bba1b95529126e2054d6b42220be3b2fea', 'pi_version': '1.0.3', 'settings.json': {'cacheWarming': 'off', 'compaction': {'enabled': True, 'keepRecentTokens': 16000, 'reserveTokens': 32768}, 'defaultModel': 'cybertiel-35b', 'defaultProjectTrust': 'never', 'defaultProvider': 'cybertiel-local', 'defaultThinkingLevel': 'high', 'defaultTools': ['read', 'bash', 'edit', 'write', 'grep', 'find', 'ls'], 'enableAnalytics': False, 'enableInstallTelemetry': False, 'httpIdleTimeoutMs': 7200000, 'retry': {'provider': {'timeoutMs': 7200000}}}}, '2026-10-06.v22': {'brace_version': '5.0.12', 'installer_sha256': '14c5520fe3aecf5e74c086df04461de384c4118323a51b072a67e412daa73051', 'llama_commit': '7fe450e19305b828c199d602c23a8337aaa1f03b', 'managed_files': {'/opt/cybertiel/bundle/Dockerfile.agent': '0cebad8498e9b4adb2708bb0ae4f55f011a12940257194a0ff6ce49e68190735', '/opt/cybertiel/bundle/Dockerfile.llama': '1a1d5252390ec21ca20113a5c74de0a68fbdb969a9d0fb1e15abaf34166adfc0', '/opt/cybertiel/bundle/accept.cpp': 'c84ca491a847683d6b618701f0cc8dbc01f28d6429101b2ca7b421504ee3eb69', '/opt/cybertiel/bundle/agent-entrypoint.py': 'bdad280173d77fdafa6b8d0980627feef84c8a8e207c6c38625cf7af8b6ac9f7', '/opt/cybertiel/bundle/agent-policy.md': 'ee5f541ec96fefbc2c2d6eac96a9f7e5bdb81008c876bc590f3135758eed04be', '/opt/cybertiel/bundle/bash-timeout.ts': '068df4aae6b0405e53eb7455f4b51722f4c1574ad0d413224c1184666e80be81', '/opt/cybertiel/bundle/check-ready.py': 'd9c3e30374e448d465380ec4f7741e60a6227f632e91d215fb833e4dfada8e72', '/opt/cybertiel/bundle/cybertiel-launcher': '1f5084bae927adf5488e739feba7fee760f92303d01f95d6f896ff3d55f13bca', '/opt/cybertiel/bundle/gdb-result-check.py': '66429f53a05bcc4226a24e74b54ffca6e2e538dc06117087b1d66e557e697d47', '/opt/cybertiel/bundle/import-debug-log.py': '65919aac7a4f52e7d2c1bb48954abc83bb69d582c460dd081821597a8e61ec6a', '/opt/cybertiel/bundle/mingw-x64.cmake': '3841d3cebcc32a9107c033b4f3434edd6a4b4bfcd4840194452fc42939b5c114', '/opt/cybertiel/bundle/models.json': '647f53375a797744906f4b05718adc3a94eecf5503b238cdede073c2196c1dac', '/opt/cybertiel/bundle/pi-settings-check.mjs': '4c22b5d390e7929db10afc32d2df7fb1667e5b7bf2485540d4f1ca9a8dbdcdf0', '/opt/cybertiel/bundle/settings.json': 'ebb42a9b10b0a1632c95c2b8599aef192c3e9d9f7e03756558d177de1489f3f3', '/opt/cybertiel/bundle/toolchain-smoke.sh': 'a01bdd11f9378fd5ea34cb3e0b64a11ecb85b35a838049f4e2eabce01897e735', '/opt/cybertiel/bundle/trace-check.py': '69fd22c8431d16f6c91b1ce99ca683eb67c8b0b5961182e9b4f7c8bf92cd6afe', '/opt/cybertiel/bundle/verify-agent.py': '6739fefa9015bd8c08b0c3f3b82b11dc2af94334e61f1d3ebc40cc069b7620e4', '/opt/cybertiel/bundle/verify-pi-lock.py': 'ad9515ac567d5867eba7a78d5cffa25de9dd0fdbb01a50536e09158057813e79', '/usr/local/bin/cybertiel': '1f5084bae927adf5488e739feba7fee760f92303d01f95d6f896ff3d55f13bca'}, 'models': {'Cyber-Tiel-Coder-35B-A3B-UD-Q8_K_XL.gguf': '7509f8c8e3b2df4c7bc5966fa711478c12c2c424f2832f7933f1e46dd180feb2', 'mmproj-BF16.gguf': 'd9ce31026d1cb1f3f8d5152e2e2a014d9d2b302b6c93a7dc07bb0a0487f52837'}, 'models.json': {'providers': {'cybertiel-local': {'api': 'openai-completions', 'apiKey': '@LOCAL_KEY@', 'baseUrl': 'http://cybertiel-model:8080/v1', 'models': [{'compat': {'maxTokensField': 'max_tokens', 'supportsDeveloperRole': False, 'supportsReasoningEffort': False, 'supportsStore': False}, 'contextWindow': 262144, 'cost': {'cacheRead': 0, 'cacheWrite': 0, 'input': 0, 'output': 0}, 'id': 'cybertiel-35b', 'input': ['text', 'image'], 'maxTokens': 258048, 'name': 'CyberTiel 35B-A3B official UD-Q8_K_XL (not BF16)', 'reasoning': True, 'samplingParams': {'min_p': 0, 'temperature': 0.6, 'top_k': 20, 'top_p': 0.95}}]}}}, 'pi_lock_sha256': 'd2a441d6f2f137a0a7fe2687cda0350e2028e49724776574db337674d2097fe7', 'pi_package_sha256': '9cae3572dc8090c7fd3ff7c7662ec7bba1b95529126e2054d6b42220be3b2fea', 'pi_version': '1.0.3', 'settings.json': {'cacheWarming': 'off', 'compaction': {'enabled': True, 'keepRecentTokens': 16000, 'reserveTokens': 32768}, 'defaultModel': 'cybertiel-35b', 'defaultProjectTrust': 'never', 'defaultProvider': 'cybertiel-local', 'defaultThinkingLevel': 'high', 'defaultTools': ['read', 'bash', 'edit', 'write', 'grep', 'find', 'ls'], 'enableAnalytics': False, 'enableInstallTelemetry': False, 'httpIdleTimeoutMs': 7200000, 'retry': {'provider': {'timeoutMs': 7200000}}}}, '2026-10-06.v23': {'brace_version': '5.0.12', 'installer_sha256': '9fd30cc869df6f565aeb283b1bfde3ef9e9152d99007a09199d9dff1f8a802d9', 'llama_commit': '7fe450e19305b828c199d602c23a8337aaa1f03b', 'managed_files': {'/opt/cybertiel/bundle/Dockerfile.agent': '0cebad8498e9b4adb2708bb0ae4f55f011a12940257194a0ff6ce49e68190735', '/opt/cybertiel/bundle/Dockerfile.llama': '1a1d5252390ec21ca20113a5c74de0a68fbdb969a9d0fb1e15abaf34166adfc0', '/opt/cybertiel/bundle/accept.cpp': 'c84ca491a847683d6b618701f0cc8dbc01f28d6429101b2ca7b421504ee3eb69', '/opt/cybertiel/bundle/agent-entrypoint.py': 'bdad280173d77fdafa6b8d0980627feef84c8a8e207c6c38625cf7af8b6ac9f7', '/opt/cybertiel/bundle/agent-policy.md': 'ee5f541ec96fefbc2c2d6eac96a9f7e5bdb81008c876bc590f3135758eed04be', '/opt/cybertiel/bundle/bash-timeout.ts': '068df4aae6b0405e53eb7455f4b51722f4c1574ad0d413224c1184666e80be81', '/opt/cybertiel/bundle/check-ready.py': 'd9c3e30374e448d465380ec4f7741e60a6227f632e91d215fb833e4dfada8e72', '/opt/cybertiel/bundle/cybertiel-launcher': 'ee77dad58cf2fa4bd929aba813b85446ff52af49f2ffaf5ccc9aecfcfa32743d', '/opt/cybertiel/bundle/gdb-result-check.py': '66429f53a05bcc4226a24e74b54ffca6e2e538dc06117087b1d66e557e697d47', '/opt/cybertiel/bundle/import-debug-log.py': '65919aac7a4f52e7d2c1bb48954abc83bb69d582c460dd081821597a8e61ec6a', '/opt/cybertiel/bundle/mingw-x64.cmake': '3841d3cebcc32a9107c033b4f3434edd6a4b4bfcd4840194452fc42939b5c114', '/opt/cybertiel/bundle/models.json': '647f53375a797744906f4b05718adc3a94eecf5503b238cdede073c2196c1dac', '/opt/cybertiel/bundle/pi-settings-check.mjs': '4c22b5d390e7929db10afc32d2df7fb1667e5b7bf2485540d4f1ca9a8dbdcdf0', '/opt/cybertiel/bundle/settings.json': 'ebb42a9b10b0a1632c95c2b8599aef192c3e9d9f7e03756558d177de1489f3f3', '/opt/cybertiel/bundle/toolchain-smoke.sh': 'a01bdd11f9378fd5ea34cb3e0b64a11ecb85b35a838049f4e2eabce01897e735', '/opt/cybertiel/bundle/trace-check.py': '69fd22c8431d16f6c91b1ce99ca683eb67c8b0b5961182e9b4f7c8bf92cd6afe', '/opt/cybertiel/bundle/verify-agent.py': '6739fefa9015bd8c08b0c3f3b82b11dc2af94334e61f1d3ebc40cc069b7620e4', '/opt/cybertiel/bundle/verify-pi-lock.py': 'ad9515ac567d5867eba7a78d5cffa25de9dd0fdbb01a50536e09158057813e79', '/usr/local/bin/cybertiel': 'ee77dad58cf2fa4bd929aba813b85446ff52af49f2ffaf5ccc9aecfcfa32743d'}, 'models': {'Cyber-Tiel-Coder-35B-A3B-UD-Q8_K_XL.gguf': '7509f8c8e3b2df4c7bc5966fa711478c12c2c424f2832f7933f1e46dd180feb2', 'mmproj-BF16.gguf': 'd9ce31026d1cb1f3f8d5152e2e2a014d9d2b302b6c93a7dc07bb0a0487f52837'}, 'models.json': {'providers': {'cybertiel-local': {'api': 'openai-completions', 'apiKey': '@LOCAL_KEY@', 'baseUrl': 'http://cybertiel-model:8080/v1', 'models': [{'compat': {'maxTokensField': 'max_tokens', 'supportsDeveloperRole': False, 'supportsReasoningEffort': False, 'supportsStore': False}, 'contextWindow': 262144, 'cost': {'cacheRead': 0, 'cacheWrite': 0, 'input': 0, 'output': 0}, 'id': 'cybertiel-35b', 'input': ['text', 'image'], 'maxTokens': 258048, 'name': 'CyberTiel 35B-A3B official UD-Q8_K_XL (not BF16)', 'reasoning': True, 'samplingParams': {'min_p': 0, 'temperature': 0.6, 'top_k': 20, 'top_p': 0.95}}]}}}, 'pi_lock_sha256': 'd2a441d6f2f137a0a7fe2687cda0350e2028e49724776574db337674d2097fe7', 'pi_package_sha256': '9cae3572dc8090c7fd3ff7c7662ec7bba1b95529126e2054d6b42220be3b2fea', 'pi_version': '1.0.3', 'settings.json': {'cacheWarming': 'off', 'compaction': {'enabled': True, 'keepRecentTokens': 16000, 'reserveTokens': 32768}, 'defaultModel': 'cybertiel-35b', 'defaultProjectTrust': 'never', 'defaultProvider': 'cybertiel-local', 'defaultThinkingLevel': 'high', 'defaultTools': ['read', 'bash', 'edit', 'write', 'grep', 'find', 'ls'], 'enableAnalytics': False, 'enableInstallTelemetry': False, 'httpIdleTimeoutMs': 7200000, 'retry': {'provider': {'timeoutMs': 7200000}}}}, '2026-10-06.v24': {'brace_version': '5.0.12', 'installer_sha256': '1c7a7ad7266c58b546f0532d82fdd5f931c280b7354ad44662dec747860ed34b', 'llama_commit': '7fe450e19305b828c199d602c23a8337aaa1f03b', 'managed_files': {'/opt/cybertiel/bundle/Dockerfile.agent': '0cebad8498e9b4adb2708bb0ae4f55f011a12940257194a0ff6ce49e68190735', '/opt/cybertiel/bundle/Dockerfile.llama': '1a1d5252390ec21ca20113a5c74de0a68fbdb969a9d0fb1e15abaf34166adfc0', '/opt/cybertiel/bundle/accept.cpp': 'c84ca491a847683d6b618701f0cc8dbc01f28d6429101b2ca7b421504ee3eb69', '/opt/cybertiel/bundle/agent-entrypoint.py': 'bdad280173d77fdafa6b8d0980627feef84c8a8e207c6c38625cf7af8b6ac9f7', '/opt/cybertiel/bundle/agent-policy.md': 'ee5f541ec96fefbc2c2d6eac96a9f7e5bdb81008c876bc590f3135758eed04be', '/opt/cybertiel/bundle/bash-timeout.ts': '068df4aae6b0405e53eb7455f4b51722f4c1574ad0d413224c1184666e80be81', '/opt/cybertiel/bundle/check-ready.py': 'd9c3e30374e448d465380ec4f7741e60a6227f632e91d215fb833e4dfada8e72', '/opt/cybertiel/bundle/cybertiel-launcher': '4a4894038c5d35f40afe80a2ab52a1e33433c0088e00f1b28562445a3ed3de05', '/opt/cybertiel/bundle/gdb-result-check.py': '66429f53a05bcc4226a24e74b54ffca6e2e538dc06117087b1d66e557e697d47', '/opt/cybertiel/bundle/import-debug-log.py': '65919aac7a4f52e7d2c1bb48954abc83bb69d582c460dd081821597a8e61ec6a', '/opt/cybertiel/bundle/mingw-x64.cmake': '3841d3cebcc32a9107c033b4f3434edd6a4b4bfcd4840194452fc42939b5c114', '/opt/cybertiel/bundle/models.json': '647f53375a797744906f4b05718adc3a94eecf5503b238cdede073c2196c1dac', '/opt/cybertiel/bundle/pi-settings-check.mjs': '4c22b5d390e7929db10afc32d2df7fb1667e5b7bf2485540d4f1ca9a8dbdcdf0', '/opt/cybertiel/bundle/settings.json': 'ebb42a9b10b0a1632c95c2b8599aef192c3e9d9f7e03756558d177de1489f3f3', '/opt/cybertiel/bundle/toolchain-smoke.sh': 'a01bdd11f9378fd5ea34cb3e0b64a11ecb85b35a838049f4e2eabce01897e735', '/opt/cybertiel/bundle/trace-check.py': '69fd22c8431d16f6c91b1ce99ca683eb67c8b0b5961182e9b4f7c8bf92cd6afe', '/opt/cybertiel/bundle/verify-agent.py': '6739fefa9015bd8c08b0c3f3b82b11dc2af94334e61f1d3ebc40cc069b7620e4', '/opt/cybertiel/bundle/verify-pi-lock.py': 'ad9515ac567d5867eba7a78d5cffa25de9dd0fdbb01a50536e09158057813e79', '/usr/local/bin/cybertiel': '4a4894038c5d35f40afe80a2ab52a1e33433c0088e00f1b28562445a3ed3de05'}, 'models': {'Cyber-Tiel-Coder-35B-A3B-UD-Q8_K_XL.gguf': '7509f8c8e3b2df4c7bc5966fa711478c12c2c424f2832f7933f1e46dd180feb2', 'mmproj-BF16.gguf': 'd9ce31026d1cb1f3f8d5152e2e2a014d9d2b302b6c93a7dc07bb0a0487f52837'}, 'models.json': {'providers': {'cybertiel-local': {'api': 'openai-completions', 'apiKey': '@LOCAL_KEY@', 'baseUrl': 'http://cybertiel-model:8080/v1', 'models': [{'compat': {'maxTokensField': 'max_tokens', 'supportsDeveloperRole': False, 'supportsReasoningEffort': False, 'supportsStore': False}, 'contextWindow': 262144, 'cost': {'cacheRead': 0, 'cacheWrite': 0, 'input': 0, 'output': 0}, 'id': 'cybertiel-35b', 'input': ['text', 'image'], 'maxTokens': 258048, 'name': 'CyberTiel 35B-A3B official UD-Q8_K_XL (not BF16)', 'reasoning': True, 'samplingParams': {'min_p': 0, 'temperature': 0.6, 'top_k': 20, 'top_p': 0.95}}]}}}, 'pi_lock_sha256': 'd2a441d6f2f137a0a7fe2687cda0350e2028e49724776574db337674d2097fe7', 'pi_package_sha256': '9cae3572dc8090c7fd3ff7c7662ec7bba1b95529126e2054d6b42220be3b2fea', 'pi_version': '1.0.3', 'settings.json': {'cacheWarming': 'off', 'compaction': {'enabled': True, 'keepRecentTokens': 16000, 'reserveTokens': 32768}, 'defaultModel': 'cybertiel-35b', 'defaultProjectTrust': 'never', 'defaultProvider': 'cybertiel-local', 'defaultThinkingLevel': 'high', 'defaultTools': ['read', 'bash', 'edit', 'write', 'grep', 'find', 'ls'], 'enableAnalytics': False, 'enableInstallTelemetry': False, 'httpIdleTimeoutMs': 7200000, 'retry': {'provider': {'timeoutMs': 7200000}}}}, '2026-10-06.v25': {'brace_version': '5.0.12', 'installer_sha256': '9b43a8b7f04162391a892c717c6377973edd2722f171ac034951e68bea7c0761', 'llama_commit': '7fe450e19305b828c199d602c23a8337aaa1f03b', 'managed_files': {'/opt/cybertiel/bundle/Dockerfile.agent': '0cebad8498e9b4adb2708bb0ae4f55f011a12940257194a0ff6ce49e68190735', '/opt/cybertiel/bundle/Dockerfile.llama': '1a1d5252390ec21ca20113a5c74de0a68fbdb969a9d0fb1e15abaf34166adfc0', '/opt/cybertiel/bundle/accept.cpp': 'c84ca491a847683d6b618701f0cc8dbc01f28d6429101b2ca7b421504ee3eb69', '/opt/cybertiel/bundle/agent-entrypoint.py': 'bdad280173d77fdafa6b8d0980627feef84c8a8e207c6c38625cf7af8b6ac9f7', '/opt/cybertiel/bundle/agent-policy.md': 'ee5f541ec96fefbc2c2d6eac96a9f7e5bdb81008c876bc590f3135758eed04be', '/opt/cybertiel/bundle/bash-timeout.ts': '068df4aae6b0405e53eb7455f4b51722f4c1574ad0d413224c1184666e80be81', '/opt/cybertiel/bundle/check-ready.py': 'd9c3e30374e448d465380ec4f7741e60a6227f632e91d215fb833e4dfada8e72', '/opt/cybertiel/bundle/cybertiel-launcher': 'dbedf6586b35f3783d4d5216e38d6edc6cd35f821a4e4950f4f0b18b7f41d8a7', '/opt/cybertiel/bundle/gdb-result-check.py': '66429f53a05bcc4226a24e74b54ffca6e2e538dc06117087b1d66e557e697d47', '/opt/cybertiel/bundle/import-debug-log.py': '65919aac7a4f52e7d2c1bb48954abc83bb69d582c460dd081821597a8e61ec6a', '/opt/cybertiel/bundle/mingw-x64.cmake': '3841d3cebcc32a9107c033b4f3434edd6a4b4bfcd4840194452fc42939b5c114', '/opt/cybertiel/bundle/models.json': '647f53375a797744906f4b05718adc3a94eecf5503b238cdede073c2196c1dac', '/opt/cybertiel/bundle/pi-settings-check.mjs': '4c22b5d390e7929db10afc32d2df7fb1667e5b7bf2485540d4f1ca9a8dbdcdf0', '/opt/cybertiel/bundle/settings.json': 'ebb42a9b10b0a1632c95c2b8599aef192c3e9d9f7e03756558d177de1489f3f3', '/opt/cybertiel/bundle/toolchain-smoke.sh': 'a01bdd11f9378fd5ea34cb3e0b64a11ecb85b35a838049f4e2eabce01897e735', '/opt/cybertiel/bundle/trace-check.py': '69fd22c8431d16f6c91b1ce99ca683eb67c8b0b5961182e9b4f7c8bf92cd6afe', '/opt/cybertiel/bundle/verify-agent.py': '6739fefa9015bd8c08b0c3f3b82b11dc2af94334e61f1d3ebc40cc069b7620e4', '/opt/cybertiel/bundle/verify-pi-lock.py': 'ad9515ac567d5867eba7a78d5cffa25de9dd0fdbb01a50536e09158057813e79', '/usr/local/bin/cybertiel': 'dbedf6586b35f3783d4d5216e38d6edc6cd35f821a4e4950f4f0b18b7f41d8a7'}, 'models': {'Cyber-Tiel-Coder-35B-A3B-UD-Q8_K_XL.gguf': '7509f8c8e3b2df4c7bc5966fa711478c12c2c424f2832f7933f1e46dd180feb2', 'mmproj-BF16.gguf': 'd9ce31026d1cb1f3f8d5152e2e2a014d9d2b302b6c93a7dc07bb0a0487f52837'}, 'models.json': {'providers': {'cybertiel-local': {'baseUrl': 'http://cybertiel-model:8080/v1', 'api': 'openai-completions', 'apiKey': '@LOCAL_KEY@', 'models': [{'id': 'cybertiel-35b', 'name': 'CyberTiel 35B-A3B official UD-Q8_K_XL (not BF16)', 'reasoning': True, 'input': ['text', 'image'], 'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0}, 'contextWindow': 262144, 'maxTokens': 258048, 'samplingParams': {'temperature': 0.6, 'top_p': 0.95, 'top_k': 20, 'min_p': 0}, 'compat': {'supportsStore': False, 'supportsDeveloperRole': False, 'supportsReasoningEffort': False, 'maxTokensField': 'max_tokens'}}]}}}, 'pi_lock_sha256': 'd2a441d6f2f137a0a7fe2687cda0350e2028e49724776574db337674d2097fe7', 'pi_package_sha256': '9cae3572dc8090c7fd3ff7c7662ec7bba1b95529126e2054d6b42220be3b2fea', 'pi_version': '1.0.3', 'settings.json': {'defaultProvider': 'cybertiel-local', 'defaultModel': 'cybertiel-35b', 'defaultThinkingLevel': 'high', 'defaultProjectTrust': 'never', 'httpIdleTimeoutMs': 7200000, 'retry': {'provider': {'timeoutMs': 7200000}}, 'defaultTools': ['read', 'bash', 'edit', 'write', 'grep', 'find', 'ls'], 'compaction': {'enabled': True, 'reserveTokens': 32768, 'keepRecentTokens': 16000}, 'enableInstallTelemetry': False, 'enableAnalytics': False, 'cacheWarming': 'off'}}, '2026-10-06.v25-r3': {'brace_version': '5.0.12', 'installer_sha256': 'd66dd8be840d75d35954df58de67b6b8cbc56e9809129bd6786106e941c76d45', 'llama_commit': '7fe450e19305b828c199d602c23a8337aaa1f03b', 'managed_files': {'/opt/cybertiel/bundle/Dockerfile.agent': 'b0eede34189afa84537b7ff6fd47830d82b81171e7899cd7c3c4edad6460f858', '/opt/cybertiel/bundle/Dockerfile.llama': '54869f728690ba794f07e6f48cc0d6cde8eb3513fe52c573e70331e1865e439a', '/opt/cybertiel/bundle/accept.cpp': 'c84ca491a847683d6b618701f0cc8dbc01f28d6429101b2ca7b421504ee3eb69', '/opt/cybertiel/bundle/agent-entrypoint.py': 'bdad280173d77fdafa6b8d0980627feef84c8a8e207c6c38625cf7af8b6ac9f7', '/opt/cybertiel/bundle/agent-policy.md': 'ee5f541ec96fefbc2c2d6eac96a9f7e5bdb81008c876bc590f3135758eed04be', '/opt/cybertiel/bundle/bash-timeout.ts': '068df4aae6b0405e53eb7455f4b51722f4c1574ad0d413224c1184666e80be81', '/opt/cybertiel/bundle/check-ready.py': '10480a29b09e77544f35b4cb0b7c2c9b68e8847885b9adfa0f66e951968f3725', '/opt/cybertiel/bundle/cybertiel-launcher': 'aaf361d02fbd53f8e2b9feac8aa80a72bdf40aa3fd85ac0599c46bdcdab23591', '/opt/cybertiel/bundle/gdb-result-check.py': '66429f53a05bcc4226a24e74b54ffca6e2e538dc06117087b1d66e557e697d47', '/opt/cybertiel/bundle/import-debug-log.py': '65919aac7a4f52e7d2c1bb48954abc83bb69d582c460dd081821597a8e61ec6a', '/opt/cybertiel/bundle/mingw-x64.cmake': '3841d3cebcc32a9107c033b4f3434edd6a4b4bfcd4840194452fc42939b5c114', '/opt/cybertiel/bundle/models.json': '647f53375a797744906f4b05718adc3a94eecf5503b238cdede073c2196c1dac', '/opt/cybertiel/bundle/pi-settings-check.mjs': '4c22b5d390e7929db10afc32d2df7fb1667e5b7bf2485540d4f1ca9a8dbdcdf0', '/opt/cybertiel/bundle/settings.json': 'ebb42a9b10b0a1632c95c2b8599aef192c3e9d9f7e03756558d177de1489f3f3', '/opt/cybertiel/bundle/toolchain-smoke.sh': 'c0bbcfb8029a8b818f564cf8a59b64b869bb7ab0eae59e17e56f159c84595d12', '/opt/cybertiel/bundle/trace-check.py': '69fd22c8431d16f6c91b1ce99ca683eb67c8b0b5961182e9b4f7c8bf92cd6afe', '/opt/cybertiel/bundle/verify-agent.py': '6739fefa9015bd8c08b0c3f3b82b11dc2af94334e61f1d3ebc40cc069b7620e4', '/opt/cybertiel/bundle/verify-pi-lock.py': '8dd085e1211f8434396e54098a37fad1dfa5b5f7754be034a4ff22042b202e12', '/usr/local/bin/cybertiel': 'aaf361d02fbd53f8e2b9feac8aa80a72bdf40aa3fd85ac0599c46bdcdab23591', '/opt/cybertiel/bundle/pi-sri-manifest.json': '0ccc765161d1a5023ab8ac02f06642d99cf51156738a76075362af3f2ec56bd8'}, 'models': {'Cyber-Tiel-Coder-35B-A3B-UD-Q8_K_XL.gguf': '7509f8c8e3b2df4c7bc5966fa711478c12c2c424f2832f7933f1e46dd180feb2', 'mmproj-BF16.gguf': 'd9ce31026d1cb1f3f8d5152e2e2a014d9d2b302b6c93a7dc07bb0a0487f52837'}, 'models.json': {'providers': {'cybertiel-local': {'baseUrl': 'http://cybertiel-model:8080/v1', 'api': 'openai-completions', 'apiKey': '@LOCAL_KEY@', 'models': [{'id': 'cybertiel-35b', 'name': 'CyberTiel 35B-A3B official UD-Q8_K_XL (not BF16)', 'reasoning': True, 'input': ['text', 'image'], 'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0}, 'contextWindow': 262144, 'maxTokens': 258048, 'samplingParams': {'temperature': 0.6, 'top_p': 0.95, 'top_k': 20, 'min_p': 0}, 'compat': {'supportsStore': False, 'supportsDeveloperRole': False, 'supportsReasoningEffort': False, 'maxTokensField': 'max_tokens'}}]}}}, 'pi_lock_sha256': 'd2a441d6f2f137a0a7fe2687cda0350e2028e49724776574db337674d2097fe7', 'pi_package_sha256': '9cae3572dc8090c7fd3ff7c7662ec7bba1b95529126e2054d6b42220be3b2fea', 'pi_version': '1.0.3', 'settings.json': {'defaultProvider': 'cybertiel-local', 'defaultModel': 'cybertiel-35b', 'defaultThinkingLevel': 'high', 'defaultProjectTrust': 'never', 'httpIdleTimeoutMs': 7200000, 'retry': {'provider': {'timeoutMs': 7200000}}, 'defaultTools': ['read', 'bash', 'edit', 'write', 'grep', 'find', 'ls'], 'compaction': {'enabled': True, 'reserveTokens': 32768, 'keepRecentTokens': 16000}, 'enableInstallTelemetry': False, 'enableAnalytics': False, 'cacheWarming': 'off'}, 'pi_derived_lock_sha256': '1d93efc1f55498590ec6d3c8aabda72654a22f67360c2507906c9c5449e0da0a', 'pi_sri_manifest_sha256': '0ccc765161d1a5023ab8ac02f06642d99cf51156738a76075362af3f2ec56bd8'}}
BASE = Path('/opt/cybertiel')
DATA = Path('/srv/cybertiel')
STATUSES = {'PASS','FAIL','WARN','UNTESTED','NOT_APPLICABLE'}
MAX_JSON = 16*1024*1024
TOOLS = ['read','bash','edit','write','grep','find','ls']

ADVISORIES = ['GHSA-q2hr-2g5m-vwhr','GHSA-qhr7-859c-m2p7','GHSA-6j4f-fj2g-mc7p']
READY_BINDINGS = {'runtime_config_sha256': 'runtime.env', 'agent_models_sha256': 'config/models.json', 'agent_settings_sha256': 'config/settings.json', 'agent_policy_sha256': 'bundle/agent-policy.md', 'agent_bash_timeout_extension_sha256': 'bundle/bash-timeout.ts', 'agent_entrypoint_sha256': 'bundle/agent-entrypoint.py', 'agent_settings_checker_sha256': 'bundle/pi-settings-check.mjs', 'node_npm_version_sha256': 'locks/node-npm-version.json', 'llama_source_provenance_sha256': 'locks/llama-source-provenance.json', 'llama_dpkg_inventory_sha256': 'locks/llama-dpkg-versions.txt', 'agent_dpkg_inventory_sha256': 'locks/agent-dpkg-versions.txt', 'host_hardware_sha256': 'locks/host-hardware.json', 'docker_version_sha256': 'locks/docker-version.json', 'docker_security_options_sha256': 'locks/docker-security-options.json', 'host_copy_fail_mitigation_sha256': 'locks/host-copy-fail-mitigation.json', 'docker_network_sha256': 'locks/docker-network.json', 'model_container_sha256': 'locks/model-container.json', 'model_seccomp_mode_sha256': 'locks/model-seccomp-mode.txt', 'model_apparmor_profile_sha256': 'locks/model-apparmor-profile.txt', 'model_props_sha256': 'locks/model-props.json', 'pi_published_shrinkwrap_sha256': 'locks/pi-published-shrinkwrap.json', 'pi_installed_tree_sha256': 'locks/pi-installed-tree.json', 'pi_official_install_package_sha256': 'locks/pi-official-install-package.json', 'pi_official_install_lock_sha256': 'locks/pi-official-install-package-lock.json', 'pi_lock_equivalence_sha256': 'locks/pi-lock-equivalence.json', 'agent_config_isolation_sha256': 'locks/agent-config-isolation.txt', 'toolchain_smoke_sha256': 'locks/toolchain-smoke.txt'}

def ready_bindings(release):
    result=dict(READY_BINDINGS)
    if release in ('2026-10-05.v17','2026-10-06.v18','2026-10-06.v19','2026-10-06.v20','2026-10-06.v21','2026-10-06.v22','2026-10-06.v23','2026-10-06.v24','2026-10-06.v25','2026-10-06.v25-r3'):
        result.pop('pi_published_shrinkwrap_sha256')
        result.pop('pi_lock_equivalence_sha256')
        result['pi_installed_lock_sha256']='locks/pi-installed-lock.json'
        result['pi_lock_verification_sha256']='locks/pi-lock-verification.json'
        result['pi_installed_tree_check_sha256']='locks/pi-installed-tree-check.json'
    if release == '2026-10-06.v25-r3':
        result['pi_sri_manifest_sha256']='locks/pi-sri-manifest.json'
        result['pi_derived_install_lock_sha256']='locks/pi-derived-install-package-lock.json'
    if release == '2026-10-06.v25-r3':
        result['pi_sri_manifest_sha256']='locks/pi-sri-manifest.json'
        result['pi_derived_install_lock_sha256']='locks/pi-derived-install-package-lock.json'
    return result

def live_lock_problems(proof,baseline):
    if not isinstance(proof,dict):return ['missing_or_invalid_proof']
    errors=[]
    for field,expected in [('status','PASS'),('pi_version','1.0.3'),('brace_expansion','5.0.12'),
                           ('lock_sha256',baseline.get('pi_derived_lock_sha256',baseline['pi_lock_sha256'])),('package_sha256',baseline['pi_package_sha256'])]:
        if proof.get(field)!=expected:errors.append(field)
    for field in ('release_hashes_checked','installed_metadata_checked'):
        if proof.get(field) is not True:errors.append(field)
    if 'pi_derived_lock_sha256' in baseline:
        for key,expected in [('official_lock_sha256',baseline['pi_lock_sha256']),('derived_lock_sha256',baseline['pi_derived_lock_sha256']),('sri_manifest_sha256',baseline['pi_sri_manifest_sha256'])]:
            if proof.get(key)!=expected:errors.append(key)
    if 'pi_derived_lock_sha256' in baseline:
        for key,expected in [('official_lock_sha256',baseline['pi_lock_sha256']),('derived_lock_sha256',baseline['pi_derived_lock_sha256']),('sri_manifest_sha256',baseline['pi_sri_manifest_sha256'])]:
            if proof.get(key)!=expected:errors.append(key)
    installed=proof.get('installed_packages')
    if not isinstance(installed,dict) or len(installed)<2:return errors+['installed_packages']
    required={'@earendil-works/pi-coding-agent':'1.0.3','brace-expansion':'5.0.12'}
    for name,version in required.items():
        values=[v.get('version') for v in installed.values() if isinstance(v,dict) and v.get('name')==name]
        if not values or any(v!=version for v in values):errors.append('installed_'+name)
    return errors

class CheckError(Exception): pass

def no_duplicates(pairs):
    d={}
    for k,v in pairs:
        if k in d: raise CheckError('duplicate JSON property')
        d[k]=v
    return d

def parse_json(raw):
    if len(raw)>MAX_JSON: raise CheckError('JSON exceeds limit')
    try:
        obj=json.loads(raw,object_pairs_hook=no_duplicates,
                          parse_constant=lambda _: (_ for _ in ()).throw(CheckError('non-finite JSON')))
        todo=[(obj,0)];nodes=0
        while todo:
            item,depth=todo.pop();nodes+=1
            if depth>64 or nodes>200000:raise CheckError('JSON depth/node limit')
            if isinstance(item,dict):todo.extend((v,depth+1) for v in item.values())
            elif isinstance(item,list):todo.extend((v,depth+1) for v in item)
        return obj
    except (ValueError,UnicodeError,RecursionError) as e: raise CheckError('malformed JSON') from e

def exact_int(x,lo,hi): return type(x) is int and lo<=x<=hi

def ver3(v):
    if not isinstance(v,str): return None
    m=re.fullmatch(r'(\d+)\.(\d+)\.(\d+)(?:[-+][A-Za-z0-9.+~-]+)?',v)
    return tuple(map(int,m.groups())) if m else None

def brace_affected(v):
    t=ver3(v)
    if t is None or '-' in v:return None
    # Union of the three recorded advisories; NOT a general vulnerability scanner.
    return t<(1,1,21) or (2,0,0)<=t<(2,1,7) or (3,0,0)<=t<(3,0,9) or (4,0,0)<=t<(5,0,12)

def stat_identity(s): return (s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns)

def open_managed(path, *,owner=0, max_bytes=MAX_JSON):
    """Descriptor-relative walk: reject symlink parents/leaves, FIFO/devices,
    writable managed parents, foreign ownership, hardlinked leaves. No blocking
    open of an attacker-controlled FIFO. Does not inspect any user project file.
    """
    p=Path(path)
    if not p.is_absolute() or '..' in p.parts: raise CheckError('unsafe managed path')
    fd=os.open('/',os.O_RDONLY|os.O_DIRECTORY|os.O_CLOEXEC)
    try:
        for part in p.parts[1:-1]:
            nxt=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC,dir_fd=fd)
            os.close(fd);fd=nxt;s=os.fstat(fd)
            if s.st_uid!=owner or stat.S_IMODE(s.st_mode)&0o022: raise CheckError('unsafe managed parent owner/mode')
        leaf=os.open(p.name,os.O_RDONLY|os.O_NONBLOCK|os.O_NOFOLLOW|os.O_CLOEXEC,dir_fd=fd)
        try:
            s=os.fstat(leaf)
            if not stat.S_ISREG(s.st_mode): raise CheckError('managed input not regular')
            if s.st_uid!=owner or stat.S_IMODE(s.st_mode)&0o022 or s.st_nlink!=1: raise CheckError('unsafe managed input owner/mode/link count')
            if max_bytes is not None and s.st_size>max_bytes: raise CheckError('managed input exceeds limit')
            return leaf,s
        except BaseException: os.close(leaf);raise
    finally: os.close(fd)

def open_managed_dir(path, *,owner=0):
    """Descriptor-relative no-follow directory open for a persistent advisory-lock anchor."""
    p=Path(path)
    if not p.is_absolute() or '..' in p.parts: raise CheckError('unsafe managed directory path')
    fd=os.open('/',os.O_RDONLY|os.O_DIRECTORY|os.O_CLOEXEC)
    try:
        for part in p.parts[1:]:
            nxt=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC,dir_fd=fd)
            os.close(fd);fd=nxt;s=os.fstat(fd)
            if s.st_uid!=owner or stat.S_IMODE(s.st_mode)&0o022:
                raise CheckError('unsafe managed directory owner/mode')
        return fd,os.fstat(fd)
    except BaseException:
        os.close(fd);raise

def read_managed(path,max_bytes=MAX_JSON):
    fd,s=open_managed(path,max_bytes=max_bytes)
    try:
        chunks=[];left=max_bytes+1
        while left:
            b=os.read(fd,min(1024*1024,left))
            if not b:break
            chunks.append(b);left-=len(b)
        raw=b''.join(chunks)
        if len(raw)>max_bytes or stat_identity(s)!=stat_identity(os.fstat(fd)):raise CheckError('file changed during read/oversize')
        return raw,s
    finally:os.close(fd)

def managed_hash(path,timeout=3600):
    fd,s=open_managed(path,max_bytes=None)
    try:
        t=time.monotonic();h=hashlib.sha256()
        while True:
            if time.monotonic()-t>timeout:raise CheckError('hash deadline exceeded')
            b=os.read(fd,8*1024*1024)
            if not b:break
            h.update(b)
        if stat_identity(s)!=stat_identity(os.fstat(fd)):raise CheckError('file changed while hashing')
        # Reopen the path to detect replacement while the old FD was hashed.
        f2,s2=open_managed(path,max_bytes=None);os.close(f2)
        if stat_identity(s)!=stat_identity(s2):raise CheckError('pathname replaced while hashing')
        return h.hexdigest(),s.st_size
    finally:os.close(fd)

def read_upload(path,limit=2*1024*1024):
    # User-owned upload is allowed as DATA only. Avoid check-then-open/FIFO races.
    fd=os.open(path,os.O_RDONLY|os.O_NONBLOCK|os.O_NOFOLLOW|os.O_CLOEXEC)
    try:
        a=os.fstat(fd)
        if not stat.S_ISREG(a.st_mode) or a.st_size>limit:raise CheckError('upload type/size')
        parts=[];remaining=limit+1
        while remaining:
            b=os.read(fd,min(remaining,65536))
            if not b:break
            parts.append(b);remaining-=len(b)
        raw=b''.join(parts)
        if len(raw)>limit or stat_identity(a)!=stat_identity(os.fstat(fd)):raise CheckError('upload changed/oversize')
        p=os.lstat(path)
        if not stat.S_ISREG(p.st_mode) or stat_identity(p)!=stat_identity(a):raise CheckError('upload pathname replaced')
        return raw
    finally:os.close(fd)

def read_system(path,cap=1024*1024):
    # Fixed OS paths only; some legitimate distro system files are symlinks.
    with open(path,'rb') as f: raw=f.read(cap+1)
    if len(raw)>cap:raise CheckError('system input exceeds limit')
    return raw

def find_command(name):
    if not re.fullmatch(r'[A-Za-z0-9_.+-]+',name):return None
    for d in ('/usr/bin','/usr/sbin','/bin','/sbin'):
        p=Path(d)/name
        try:
            real=p.resolve(strict=True);s=real.stat()
            if not stat.S_ISREG(s.st_mode) or s.st_uid!=0 or stat.S_IMODE(s.st_mode)&0o022:continue
            if any(q.stat().st_uid!=0 or stat.S_IMODE(q.stat().st_mode)&0o022 for q in real.parents):continue
            # Validate both the canonical executable and the invoked alias path.
            # modprobe is a kmod symlink: resolving argv[0] changes its applet.
            if p.lstat().st_uid!=0:continue
            if any(q.stat().st_uid!=0 or stat.S_IMODE(q.stat().st_mode)&0o022 for q in p.parents):continue
            if os.access(real,os.X_OK):return str(p)
        except OSError:continue
    return None

def safe_env():
    return {'PATH':'/usr/sbin:/usr/bin:/sbin:/bin','HOME':'/nonexistent',
            'LC_ALL':'C','LANG':'C','TZ':'UTC',
            'DOCKER_HOST':'unix:///var/run/docker.sock','DOCKER_CONFIG':'/nonexistent',
            'PYTHONDONTWRITEBYTECODE':'1','NO_COLOR':'1'}

def bounded_run(argv,timeout=20,stdin=None,limit=MAX_JSON,env=None):
    """Real subprocess deadline and capped combined output; kill owned process
    group on overflow/timeout, including descendants that retain output pipes.
    Commands are predetermined argv lists; never a shell from server files.
    """
    if not isinstance(argv,list) or not argv or not os.path.isabs(argv[0]):raise CheckError('absolute command argv required')
    start=time.monotonic();bufs={'stdout':bytearray(),'stderr':bytearray()};why=None
    inf=tempfile.TemporaryFile()
    if stdin is not None:inf.write(stdin if isinstance(stdin,bytes) else stdin.encode());inf.seek(0)
    try:
        p=subprocess.Popen(argv,cwd='/',env=env or safe_env(),stdin=inf if stdin is not None else subprocess.DEVNULL,
                           stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    except OSError:
        inf.close();return {'rc':None,'reason':'SPAWN_FAILED','stdout':b'','stderr':b'','seconds':0}
    sel=selectors.DefaultSelector()
    for k,s in [('stdout',p.stdout),('stderr',p.stderr)]:os.set_blocking(s.fileno(),False);sel.register(s,selectors.EVENT_READ,k)
    try:
        while sel.get_map():
            if time.monotonic()-start>timeout:why='TIMEOUT';break
            for key,_ in sel.select(min(0.1,max(0,timeout-(time.monotonic()-start)))):
                try:b=os.read(key.fileobj.fileno(),65536)
                except BlockingIOError:continue
                if not b:sel.unregister(key.fileobj);continue
                if sum(len(v) for v in bufs.values())+len(b)>limit:why='OUTPUT_LIMIT';break
                bufs[key.data].extend(b)
            if why:break
        if why:
            try:os.killpg(p.pid,signal.SIGKILL)
            except ProcessLookupError:pass
        try:p.wait(timeout=max(0.1,timeout-(time.monotonic()-start)))
        except subprocess.TimeoutExpired:
            why='TIMEOUT'
            try:os.killpg(p.pid,signal.SIGKILL)
            except ProcessLookupError:pass
            p.wait(timeout=5)
    finally:
        sel.close();p.stdout.close();p.stderr.close();inf.close()
    return {'rc':p.returncode,'reason':why,'stdout':bytes(bufs['stdout']),'stderr':bytes(bufs['stderr']),
            'seconds':round(time.monotonic()-start,3)}

def docker_args(command):
    p=find_command('docker')
    if not p:raise CheckError('Docker CLI unavailable')
    return [p,'--host','unix:///var/run/docker.sock',*command]

def docker_json(command):
    r=bounded_run(docker_args(command),timeout=25)
    if r['rc']!=0 or r['reason']:raise CheckError('Docker unavailable, timeout, or object absent')
    return parse_json(r['stdout'])

def image_ids(raw):
    try: text=raw.decode('ascii')
    except UnicodeError:raise CheckError('runtime.env not ASCII')
    out={}
    for l in text.splitlines():
        m=re.fullmatch(r'(LLAMA_IMAGE|AGENT_IMAGE)=(sha256:[0-9a-f]{64})',l)
        if not m or m[1] in out:raise CheckError('unsafe or duplicate runtime.env assignment')
        out[m[1]]=m[2]
    if set(out)!={'LLAMA_IMAGE','AGENT_IMAGE'}:raise CheckError('incomplete runtime.env')
    return out

def network_problems(n,release):
    if not isinstance(n,dict):return ['wrong network schema']
    bad=[]
    if any(n.get(k) is not None and not isinstance(n[k],dict) for k in ('Labels','Options','Containers')):return ['wrong nested network schema']
    if any(not isinstance(v,dict) for v in (n.get('Containers') or {}).values()):return ['wrong network endpoint schema']
    if n.get('Name')!='cybertiel-internal' or n.get('Driver')!='bridge':bad.append('network identity/driver')
    if n.get('Internal') is not True:bad.append('not internal')
    if n.get('EnableIPv6') is not False:bad.append('IPv6 not explicitly disabled')
    if n.get('EnableIPv4',True) is not True:bad.append('IPv4 disabled')
    if (n.get('Labels') or {}).get('io.cybertiel.managed')!=release:bad.append('foreign release label')
    if (n.get('Options') or {}).get('com.docker.network.bridge.gateway_mode_ipv4')!='isolated':bad.append('missing isolated gateway')
    for v in (n.get('Containers') or {}).values():
        if v.get('Name') not in {'cybertiel-model','cybertiel-agent'} and not str(v.get('Name','')).startswith('ct-inspect-'):
            bad.append('unexpected attached container');break
    return bad

def container_problems(c,role,release,image,base=BASE,data=DATA):
    if not isinstance(c,dict):return ['wrong container schema']
    if any(not isinstance(c.get(k),dict) for k in ('HostConfig','Config','NetworkSettings')):return ['wrong nested container schema']
    h=c['HostConfig'];cfg=c['Config'];ns=c['NetworkSettings']
    if any(h.get(k) is not None and not isinstance(h[k],list) for k in ('SecurityOpt','CapDrop','CapAdd','Ulimits')):return ['wrong security array schema']
    if any(not isinstance(v,dict) for v in (h.get('Ulimits') or [])):return ['wrong ulimit schema']
    if h.get('Tmpfs') is not None and not isinstance(h['Tmpfs'],dict):return ['wrong tmpfs schema']
    if any(cfg.get(k) is not None and not isinstance(cfg[k],list) for k in ('Entrypoint','Cmd')):return ['wrong argv schema']
    if cfg.get('Labels') is not None and not isinstance(cfg['Labels'],dict):return ['wrong label schema']
    if not isinstance(ns.get('Networks'),dict) or any(not isinstance(x,dict) for x in ns['Networks'].values()):return ['wrong attached-network schema']
    if ns.get('Ports') is not None and not isinstance(ns['Ports'],dict):return ['wrong port schema']
    if not isinstance(c.get('Mounts'),list) or any(not isinstance(x,dict) for x in c['Mounts']):return ['wrong mounts schema']
    bad=[];h=c.get('HostConfig') or {};cfg=c.get('Config') or {};nets=(c.get('NetworkSettings') or {}).get('Networks') or {}
    expected_name='/cybertiel-'+role
    if c.get('Name')!=expected_name:bad.append('container name')
    if c.get('Image')!=image:bad.append('image differs from recorded image')
    if (cfg.get('Labels') or {}).get('io.cybertiel.managed')!=release:bad.append('release label')
    if cfg.get('User')!=('65534:65534' if role=='model' else '1000:1000'):bad.append('user')
    if h.get('Privileged') is not False:bad.append('privileged flag absent/true')
    if h.get('ReadonlyRootfs') is not True:bad.append('writable rootfs')
    if h.get('Init') is not True:bad.append('missing init process')
    if {str(x).upper() for x in h.get('CapDrop') or []}!={'ALL'} or h.get('CapAdd'):bad.append('capabilities')
    opts={str(x).replace('=',':',1) for x in h.get('SecurityOpt') or []}
    if not {'no-new-privileges:true','seccomp:builtin','apparmor:docker-default'}<=opts:bad.append('security options')
    if any('unconfined' in x for x in opts) or c.get('AppArmorProfile')!='docker-default':bad.append('AppArmor/seccomp unconfined')
    if h.get('NetworkMode')!='cybertiel-internal' or set(nets)!={'cybertiel-internal'}:bad.append('extra/wrong network')
    if any(x.get('GlobalIPv6Address') for x in nets.values()):bad.append('container IPv6')
    if h.get('PortBindings') or any(v for v in (c.get('NetworkSettings') or {}).get('Ports',{}).values()):bad.append('published ports')
    if h.get('PidMode')=='host' or h.get('IpcMode')=='host' or h.get('UTSMode')=='host' or h.get('UsernsMode')=='host':bad.append('host namespaces')
    if h.get('Devices') or h.get('DeviceRequests') or h.get('VolumesFrom'):bad.append('unexpected devices/volumes')
    memory=(96 if role=='model' else 16)*2**30
    if type(h.get('Memory')) is not int or h['Memory']!=memory or h.get('MemorySwap')!=memory:bad.append('memory/swap bounds')
    if h.get('PidsLimit')!=(512 if role=='model' else 1024):bad.append('PID bound')
    if role=='agent' and h.get('NanoCpus')!=8*10**9:bad.append('CPU bound')
    ul=[x for x in h.get('Ulimits') or [] if x.get('Name')=='core']
    if len(ul)!=1 or ul[0].get('Soft')!=0 or ul[0].get('Hard')!=0:bad.append('core dump limit')
    binds={('/models',str(data/'models'),False),('/run/llama-api-key',str(base/'config/api-key'),False)} if role=='model' else {('/workspace',str(data/'project'),True),('/opt/cybertiel/pi-config',str(base/'config'),False)}
    observed=set()
    for m in c.get('Mounts') or []:
        if m.get('Type')=='tmpfs':continue
        if m.get('Type')!='bind':bad.append('unexpected mount type');continue
        observed.add((m.get('Destination'),m.get('Source'),m.get('RW')))
    if observed!=binds:bad.append('bind mount set or access differs')
    tmp=h.get('Tmpfs') or {};required={'/tmp'} if role=='model' else {'/tmp','/home/node','/sessions'}
    if set(tmp)!=required:bad.append('tmpfs set')
    for dst,value in tmp.items():
        opt=set(str(value).split(','))
        if not {'rw','nosuid','nodev'}<=opt or not any(x.startswith('size=') for x in opt):bad.append('tmpfs flags/bounds');break
        if dst in {'/home/node','/sessions'} and not {'mode=0700','uid=1000','gid=1000'}<=opt:bad.append('tmpfs owner/privacy');break
    if role=='model':
        if cfg.get('Entrypoint')!=['/usr/local/bin/llama-server']:bad.append('model entrypoint')
        cmd=cfg.get('Cmd') or []
        flags={'--model':'/models/Cyber-Tiel-Coder-35B-A3B-UD-Q8_K_XL.gguf','--mmproj':'/models/mmproj-BF16.gguf','--host':'0.0.0.0','--port':'8080','--api-key-file':'/run/llama-api-key','--alias':'cybertiel-35b','--ctx-size':'262144','--parallel':'1','--cache-ram':'0','--cache-type-k':'f16','--cache-type-v':'f16','--temp':'0.6','--top-p':'0.95','--top-k':'20','--min-p':'0','--predict':'-1','--reasoning-budget':'-1','--timeout':'7200','--device':'none','--n-gpu-layers':'0'}
        flags.update({'--reasoning-format':'deepseek','--poll':'0','--batch-size':'512','--ubatch-size':'128'})
        for f,v in flags.items():
            if cmd.count(f)!=1 or cmd.index(f)+1>=len(cmd) or cmd[cmd.index(f)+1]!=v:bad.append('model flag '+f)
        logs=h.get('LogConfig') or {}
        if not isinstance(logs,dict) or logs.get('Type')!='json-file' or not isinstance(logs.get('Config'),dict) or logs['Config'].get('max-size')!='10m' or logs['Config'].get('max-file')!='3':bad.append('model log retention')
        for f in ['--threads','--threads-batch']:
            if cmd.count(f)!=1 or cmd.index(f)+1>=len(cmd) or not re.fullmatch(r'[1-9][0-9]{0,2}',str(cmd[cmd.index(f)+1])):bad.append('thread budget '+f)
        for f in ['--jinja','--no-mmproj-offload','--no-cache-idle-slots']:
            if cmd.count(f)!=1:bad.append('model flag '+f)
    else:
        if cfg.get('Entrypoint')!=['python3','/opt/cybertiel/agent-entrypoint.py']:bad.append('agent entrypoint')
        cmd=cfg.get('Cmd') or []
        if '/bin/bash' in (cfg.get('Entrypoint') or []):bad.append('shell instead of agent')
        for f in ['--no-session','--offline','--no-extensions','--no-context-files','--no-skills','--no-approve','--no-prompt-templates','--no-themes']:
            if cmd.count(f)!=1:bad.append('agent flag '+f)
        for f,v in {'-e':'/opt/cybertiel/bash-timeout.ts','--append-system-prompt':'/opt/cybertiel/agent-policy.md','--tools':'read,bash,edit,write,grep,find,ls','--provider':'cybertiel-local','--model':'cybertiel-35b'}.items():
            if cmd.count(f)!=1 or cmd.index(f)+1>=len(cmd) or cmd[cmd.index(f)+1]!=v:bad.append('agent binding '+f)
        if cfg.get('WorkingDir')!='/workspace':bad.append('agent working directory')
    return sorted(set(bad))

def props_problems(d):
    if not isinstance(d,dict):return ['schema']
    g=d.get('default_generation_settings') or {}
    if not isinstance(g,dict) or not isinstance(g.get('params'),dict) or not isinstance(d.get('modalities'),dict):return ['nested schema']
    p=g['params'];bad=[]
    if type(g.get('n_ctx')) is not int or g['n_ctx']!=262144:bad.append('context')
    if type(d.get('total_slots')) is not int or d['total_slots']!=1:bad.append('slots')
    if (d.get('modalities') or {}).get('vision') is not True:bad.append('projector')
    for k,v in [('n_predict',-1),('max_tokens',-1),('top_k',20)]:
        if type(p.get(k)) is not int or p[k]!=v:bad.append(k)
    for k,v in [('temperature',.6),('top_p',.95),('min_p',0.)]:
        q=p.get(k)
        if type(q) not in (int,float) or not math.isfinite(q) or abs(q-v)>1e-4:bad.append(k)
    return bad

def assess_tree(tree):
    """Installed npm ls tree AND package-lock/shrinkwrap. No cycles or unbounded recursion."""
    versions=set();count=0;queue=[tree]
    while queue:
        d=queue.pop();count+=1
        if count>20000:raise CheckError('dependency inventory exceeds limit')
        if not isinstance(d,dict):continue
        pk=d.get('packages')
        if isinstance(pk,dict):
            for name,e in pk.items():
                if name=='node_modules/brace-expansion' or name.endswith('/node_modules/brace-expansion'):
                    versions.add(str(e.get('version','UNKNOWN')) if isinstance(e,dict) else 'UNKNOWN')
        deps=d.get('dependencies')
        if isinstance(deps,dict):
            for n,e in deps.items():
                if n=='brace-expansion':versions.add(str(e.get('version','UNKNOWN')) if isinstance(e,dict) else 'UNKNOWN')
                queue.append(e)
    if not versions:return {'status':'UNTESTED','versions':[],'reason':'dependency not observed; not proof of absence'}
    if any(brace_affected(v) is True for v in versions):status='FAIL'
    elif any(brace_affected(v) is None for v in versions):status='UNTESTED'
    else:status='PASS'
    return {'status':status,'versions':sorted(versions),'advisories':ADVISORIES,'scope':'only the three recorded brace-expansion advisories'}

class Auditor:
    def __init__(self,args):
        self.args=args;self.rows=[];self.facts={};self.baseline=None;self.release=None;self.ids={};self.ready=None;self.container=None;self.network=None;self.trusted_images=False;self.start=time.monotonic();self.held=[]
    def add(self,id,status,text,detail=None):
        if status not in STATUSES or any(x['id']==id for x in self.rows):raise CheckError('invalid/duplicate check id')
        row={'id':id,'status':status,'message':text}
        if detail is not None:row['details']=detail
        self.rows.append(row);print(f'[{status:14}] {id}: {text}',file=sys.stderr,flush=True)
    def attempt(self,id,fn,fail='FAIL'):
        try:return fn()
        except (OSError,CheckError,ValueError,TypeError,KeyError,IndexError,AttributeError,RecursionError):
            self.add(id,fail,'Niet leesbaar, ontbrekend, onveilig of ongeldig; niet als geslaagd beschouwd.');return None
    def host(self):
        self.facts['host']={'system':platform.system(),'architecture':platform.machine(),'kernel':platform.release(),'uid':os.geteuid(),'logical_cpus':os.cpu_count()}
        self.add('host.linux','PASS' if platform.system()=='Linux' else 'FAIL','Dit controlescript is voor Linux.')
        self.add('host.root','PASS' if os.geteuid()==0 else 'UNTESTED','Rootrechten nodig voor volledige leescontrole van beheerbestanden en Docker.')
        r={}
        for l in read_system('/etc/os-release').decode(errors='replace').splitlines():
            if '=' in l:k,v=l.split('=',1);r[k]=v.strip('"')
        self.facts['host']['distribution']={k:r.get(k) for k in ('ID','VERSION_ID')}
        self.add('host.os','PASS' if r.get('ID')=='ubuntu' and r.get('VERSION_ID')=='24.04' else 'FAIL','Installer ondersteunt Ubuntu 24.04 LTS.')
        self.add('host.arch','PASS' if platform.machine()=='x86_64' else 'FAIL','x86_64 vereist.')
        cpu=read_system('/proc/cpuinfo',4*1024*1024).decode();avx=bool(re.search(r'\bavx2\b',cpu));models=[]
        for l in cpu.splitlines():
            if l.startswith('model name'):
                x=l.split(':',1)[1].strip()
                if x not in models:models.append(x)
        self.facts['host']['cpu_models']=models;self.add('host.avx2','PASS' if avx else 'FAIL','AVX2 zichtbaar aan het OS.')
        self.add('host.cpu_sku','PASS' if any('E5-2620 v4' in s for s in models) else 'WARN','Controleer geleverde CPU tegen de bestelling; andere AVX2-CPU is niet automatisch incompatibel.')
        mem={}
        for l in read_system('/proc/meminfo').decode().splitlines():
            p=l.split()
            if p[0] in {'MemTotal:','MemAvailable:','SwapTotal:','SwapFree:'}:mem[p[0][:-1]]=int(p[1])*1024
        self.facts['host']['memory_bytes']=mem
        self.add('host.ram','PASS' if mem.get('MemTotal',0)>=110*2**30 else 'FAIL','Minimaal 110 GiB zichtbaar RAM voor dit installerprofiel.')
        self.add('host.memory_pressure','WARN' if mem.get('MemAvailable',0)<4*2**30 else 'PASS','Actuele vrije RAM gemeten; geen modelperformancebewijs.')
        self.add('host.reboot','FAIL' if Path('/run/reboot-required').exists() else 'PASS','Geen openstaande Ubuntu-herstartmelding vereist.')
        for name in ('/','/srv'):
            p=Path(name)
            while not p.exists():p=p.parent
            s=os.statvfs(p);free=s.f_bavail*s.f_frsize
            self.facts.setdefault('storage',{})[name]={'free_bytes':free,'free_inodes':s.f_favail}
            self.add('disk.'+name.replace('/','root'), 'FAIL' if free<5*2**30 or s.f_favail==0 else 'PASS','Vrije schijfruimte/inodes gemeten; 90 GiB vóór verse installatie en extra projectruimte blijven nodig.')
        app=read_system('/sys/module/apparmor/parameters/enabled').strip() if Path('/sys/module/apparmor/parameters/enabled').exists() else b''
        self.add('host.apparmor','PASS' if app==b'Y' else 'FAIL','AppArmor moet actief zijn voor dit profiel.')
        loaded=Path('/sys/module/algif_aead').exists()
        self.add('host.algif_aead','FAIL' if loaded else 'PASS','algif_aead niet geladen; dit alleen bewijst geen gepatchte kernel.')
        kmod=find_command('dpkg-query');dk=find_command('dpkg');mod=find_command('modprobe')
        if kmod and dk:
            q=bounded_run([kmod,'-W','-f=${Version}','kmod'])
            v=q['stdout'].decode(errors='replace').strip()
            if q['rc']==0 and re.fullmatch(r'[0-9A-Za-z.+:~_-]{1,100}',v):
                cmp=bounded_run([dk,'--compare-versions',v,'ge','31+20240202-2ubuntu7.2'])
                self.add('host.kmod','PASS' if cmp['rc']==0 else 'FAIL','kmod vergeleken met vastgelegde Noble-mitigatie.',{'version':v})
            else:self.add('host.kmod','UNTESTED','kmod-versie niet vastgesteld.')
        else:self.add('host.kmod','UNTESTED','Geen dpkg-versiemeting.')
        try:
            b,_=read_managed('/etc/modprobe.d/disable-algif_aead.conf',65536)
            valid=bool(re.search(rb'^\s*install\s+algif_aead\s+/bin/false(?:\s|$)',b,re.M))
            self.add('host.mitigation_file','PASS' if valid else 'FAIL','Officiële blokkadeconfig gecontroleerd.')
        except (OSError,CheckError):self.add('host.mitigation_file','FAIL','Noble-mitigatiebestand ontbreekt of wijkt af; geen automatische wijziging.')
        if mod:
            q=bounded_run([mod,'-n','-v','algif_aead'])
            self.add('host.modprobe_dryrun','PASS' if q['rc']==0 and re.search(rb'(^|\s)(?:install\s+)?/bin/false(?:\s|$)',q['stdout']) else 'FAIL','Alleen modprobe dry-run; geen module geladen/verwijderd.')
        else:self.add('host.modprobe_dryrun','UNTESTED','modprobe niet beschikbaar.')
        apt=find_command('apt')
        if apt:
            q=bounded_run([apt,'list','--upgradable'],timeout=30,limit=1024*1024)
            n=sum(1 for x in q['stdout'].splitlines() if b'[upgradable from:' in x)
            self.add('host.cached_updates','WARN' if n else 'UNTESTED','Alleen bestaande lokale APT-cache bekeken, geen apt update. Nul meldingen bewijst niet dat alles actueel is.',{'cached_upgradable_count':n,'cache_online_refreshed':False})
        else:self.add('host.cached_updates','UNTESTED','APT-inventaris niet beschikbaar.')
    def installed(self):
        if self.args.installer:
            p=Path(self.args.installer)
            # Uploaded script is data, never executed/sourced.
            try:
                raw=read_upload(p);h=hashlib.sha256(raw).hexdigest();match=[r for r,b in BASELINES.items() if b['installer_sha256']==h]
                self.add('upload.installer','PASS' if match else 'FAIL','Upload vergeleken met onafhankelijke releasehash; niet uitgevoerd.',{'sha256':h,'recognized_releases':match})
                if '2026-10-05.v16' in match:self.add('audit.upload_security','FAIL','V16-upload is herkenbaar, maar de Pi 1.0.0-lock bevat de bekende brace-expansion 5.0.9-problemen; correcte hash is geen installatiegoedkeuring.',{'advisories':ADVISORIES})
            except (OSError,CheckError):self.add('upload.installer','FAIL','Opgegeven installer niet veilig leesbaar.')
        else:self.add('upload.installer','UNTESTED','Geen --installer pad opgegeven; de upload zelf is niet gecontroleerd.')
        try:self.release=read_managed(BASE/'.cybertiel-install-id',256)[0].decode().strip()
        except (OSError,CheckError,UnicodeError):
            self.add('install.release','FAIL','Geen veilig leesbare installatie gevonden. Op een nieuwe server is dat te verwachten.');return
        if self.release not in BASELINES:
            self.add('install.release','UNTESTED','Onbekende release; geen vergelijkingsbaseline. Gebruik geen hashes van een andere versie.');return
        self.baseline=BASELINES[self.release]
        self.add('install.release','PASS','Herkende installatie.',{'release':self.release})
        # Known release review finding: immutable does NOT mean current/security-fixed.
        if self.release=='2026-10-05.v16':
            self.add('audit.pi_lock_advisory','FAIL','V16 gebruikt Pi 1.0.0; de gepubliceerde dependency-lock bevat brace-expansion 5.0.9 met bekende DoS-advisories. Installatiegoedkeuring geblokkeerd tot een gecontroleerde dependency-update.',{'advisories':ADVISORIES,'evidence':'official v1.0.0 shrinkwrap + Pi v1.0.1 fix notes','exploit_run':False})
        else:
            self.add('audit.pi_pin','PASS','V17 en latere huidige profielen vereisen Pi 1.0.3 met hash-gepinde officiële installer-lock; werkelijk geïnstalleerde dependencies worden apart gecontroleerd.')
        raw=self.attempt('install.runtime_env',lambda:read_managed(BASE/'runtime.env',8192)[0])
        if raw is not None:
            ids=self.attempt('install.runtime_env_parse',lambda:image_ids(raw))
            if ids:self.ids=ids;self.add('install.runtime_env_valid','PASS','Image-ID-config veilig geparsed, niet als shellcode uitgevoerd.')
        for rel,expect in self.baseline['managed_files'].items():
            p=Path(rel);key='file.'+str(p.relative_to(BASE)).replace('/','.') if str(p).startswith(str(BASE)+'/') else 'file.launcher'
            try:
                b,s=read_managed(p,2*1024*1024);h=hashlib.sha256(b).hexdigest()
                self.add(key,'PASS' if h==expect else 'FAIL','Bestand vergeleken met extern ingebouwde baseline.',{'expected_sha256':expect,'actual_sha256':h})
            except (OSError,CheckError):self.add(key,'FAIL','Ontbrekend, veranderd of onveilig beheerd bestand.')
        for n in ('settings.json','models.json'):
            try:
                raw,s=read_managed(BASE/'config'/n,1024*1024);d=parse_json(raw);expected=self.baseline[n]
                if n=='models.json':
                    d=json.loads(json.dumps(d));provider=d['providers']['cybertiel-local'];key=provider.pop('apiKey',None)
                    if not isinstance(key,str) or not re.fullmatch(r'[A-Za-z0-9_-]{32,128}',key):raise CheckError('key shape')
                    key_bytes,_=read_managed(BASE/'config/api-key',1024)
                    if key!=key_bytes.decode().strip():raise CheckError('model key mismatch')
                    expected=json.loads(json.dumps(expected));expected['providers']['cybertiel-local'].pop('apiKey',None)
                if d!=expected:raise CheckError('config baseline mismatch')
                if stat.S_IMODE(s.st_mode)&0o007:raise CheckError('config world readable')
                self.add('config.'+n,'PASS','Structuur/instellingen vergeleken; geheime inhoud niet in rapport.')
            except (OSError,CheckError,ValueError,TypeError,KeyError,UnicodeError):self.add('config.'+n,'FAIL','Config ontbreekt, wijkt af, heeft onjuiste rechten of sleutelbinding.')
        try:
            b,s=read_managed(BASE/'config/api-key',1024)
            good=s.st_uid==0 and s.st_gid==65534 and stat.S_IMODE(s.st_mode)==0o640 and bool(re.fullmatch(rb'[A-Za-z0-9_-]{32,128}\n?',b))
            self.add('config.key_permissions','PASS' if good else 'FAIL','API-sleutel alleen op vorm/rechten gecontroleerd; geen inhoud of sleutelhash gepubliceerd.')
        except (OSError,CheckError):self.add('config.key_permissions','FAIL','API-sleutel ontbreekt of onveilig beheerd.')
        try:
            raw,s=read_managed(BASE/'READY.json');d=parse_json(raw)
            if not isinstance(d,dict) or d.get('installer_id')!=self.release or d.get('status')!='INSTALLATION_SMOKE_PASS':raise CheckError('READY identity')
            self.ready=d;self.add('ready.record','PASS','Historisch rooktestverslag aanwezig; dit is niet automatisch bewijs voor de huidige installatie.')
            for key,rel in ready_bindings(self.release).items():
                try:
                    b,_=read_managed(BASE/rel);match=hashlib.sha256(b).hexdigest()==d.get(key)
                    self.add('ready.binding.'+key,'PASS' if match else 'FAIL','Opgeslagen bewijs/config opnieuw gehasht; geen live functieclaim.')
                except (OSError,CheckError):self.add('ready.binding.'+key,'FAIL','Gebonden bewijs/config ontbreekt of onveilig.')
        except (OSError,CheckError,ValueError):self.add('ready.record','FAIL','READY ontbreekt of is geen geldig installatiebewijs.')
        if self.release in ('2026-10-05.v17','2026-10-06.v18','2026-10-06.v19','2026-10-06.v20','2026-10-06.v21','2026-10-06.v22','2026-10-06.v23','2026-10-06.v24','2026-10-06.v25','2026-10-06.v25-r3'):
            expected_files={'pi-official-install-package.json':self.baseline['pi_package_sha256'],
                'pi-official-install-package-lock.json':self.baseline['pi_lock_sha256'],
                'pi-installed-lock.json':self.baseline.get('pi_derived_lock_sha256',self.baseline['pi_lock_sha256'])}
            if self.release=='2026-10-06.v25-r3':
                expected_files.update({'pi-derived-install-package-lock.json':self.baseline['pi_derived_lock_sha256'],'pi-sri-manifest.json':self.baseline['pi_sri_manifest_sha256']})
            for name,expected in expected_files.items():
                try:
                    value=hashlib.sha256(read_managed(BASE/'locks'/name)[0]).hexdigest()
                    self.add('pi.official_hash.'+name,'PASS' if value==expected else 'FAIL','Bestand tegen onafhankelijke officiële v1.0.3-releasehash gecontroleerd; niet alleen tegen READY.')
                except (OSError,CheckError):self.add('pi.official_hash.'+name,'FAIL','Officieel/installed lockbestand ontbreekt of is onveilig.')
        for path in ('pi-official-install-package-lock.json', 'pi-published-shrinkwrap.json' if self.release=='2026-10-05.v16' else 'pi-installed-lock.json', 'pi-installed-tree.json'):
            try:
                tree=parse_json(read_managed(BASE/'locks'/path)[0]);r=assess_tree(tree)
                self.add('dependencies.'+path,r.pop('status'),'Vastgelegde dependencyversies op drie concrete advisories getoetst; inventaris is geen volledige CVE-scan.',r)
            except (OSError,CheckError,ValueError):self.add('dependencies.'+path,'UNTESTED','Dependency-inventaris ontbreekt of ongeldig.')
    def models(self):
        baseline=self.baseline or BASELINES['2026-10-05.v16']
        for name,expected in baseline['models'].items():
            key='model.'+('gguf' if name.startswith('Cyber-') else 'projector')
            try:
                fd,s=open_managed(DATA/'models'/name,max_bytes=None)
                try:head=os.read(fd,24)
                finally:os.close(fd)
                good=len(head)==24 and head[:4]==b'GGUF' and int.from_bytes(head[4:8],'little')==3
                self.add(key+'.header','PASS' if good else 'FAIL','Bestand aanwezig met GGUF-v3-header; dit is nog geen integriteitsbewijs.',{'bytes':s.st_size})
                if self.args.deep_model_hash:
                    print('SHA-256 lezen van '+name+'; dit kan veel schijf-I/O gebruiken.',file=sys.stderr,flush=True)
                    actual,size=managed_hash(DATA/'models'/name,self.args.hash_timeout)
                    self.add(key+'.hash','PASS' if actual==expected else 'FAIL','Volledig modelbestand gehasht met no-follow/object-continuïteitscontrole.',{'sha256':actual,'bytes':size})
                else:self.add(key+'.hash','UNTESTED','Volledige 38,5-GB/modelhash niet herlezen. Gebruik --deep-model-hash voor die controle.')
            except (OSError,CheckError):self.add(key,'FAIL','Model/projector ontbreekt, onveilig of veranderde tijdens controle.')
            try:
                fd,s=open_managed(DATA/'models'/(name+'.part'),max_bytes=None);os.close(fd)
                self.add(key+'.partial','WARN','Onvoltooide .part aanwezig; niet verwijderd of hervat.',{'bytes':s.st_size})
            except FileNotFoundError:pass
            except (OSError,CheckError):self.add(key+'.partial','WARN','Onveilig/onleesbaar partial-downloadpad.')
    def docker(self):
        if not find_command('docker'):
            self.add('docker.cli','FAIL','Docker niet geïnstalleerd of CLI onveilig; niets wordt geïnstalleerd.');return
        self.add('docker.cli','PASS','Docker CLI aanwezig; expliciet alleen lokale daemon gebruikt.')
        try:
            v=docker_json(['version','--format','{{json .}}']);s=v.get('Server') or {};version=s.get('Version','');t=ver3(version)
            self.add('docker.engine','PASS' if t and t[0]>=28 else 'FAIL','Engineversie voor isolated gateway mode gecontroleerd.',{'server_version':version})
            if t and t>=(29,8,0):self.add('docker.apparmor_template','UNTESTED','Engine >=29.8: docker-default kan een aangepaste template hebben; naam/enforce is geen inhoudsbewijs.')
            info=docker_json(['info','--format','{{json .}}']);sec=info.get('SecurityOptions') or []
            good=any(str(x).startswith('name=apparmor') for x in sec) and any(str(x).startswith('name=seccomp') for x in sec)
            self.add('docker.security_support','PASS' if good else 'FAIL','Daemon rapporteert AppArmor en seccomp; geen inhoudelijke firewall-/LSM-audit.')
            if any('rootless' in str(x) for x in sec) or any('userns' in str(x) for x in sec):self.add('docker.rootless_userns','UNTESTED','Dit installerprofiel is niet gekwalificeerd voor rootless/userns-remap.')
            root=info.get('DockerRootDir')
            if not isinstance(root,str) or not root.startswith('/'):raise CheckError('DockerRootDir')
            q=Path(root).resolve(strict=True);d=shutil.disk_usage(q)
            self.facts.setdefault('storage',{})['docker']={'free_bytes':d.free}
            self.add('docker.disk','PASS' if d.free>=20*2**30 else 'WARN','Werkelijke DockerRootDir-schijf gemeten; 20 GiB vrije buildreserve is richtwaarde.')
        except (OSError,CheckError,ValueError,TypeError):self.add('docker.daemon','FAIL','Lokale Docker-daemon niet volledig uitleesbaar.');return
        if not self.release or not self.ids:return
        try:
            ns=docker_json(['network','inspect','cybertiel-internal'])
            if not isinstance(ns,list) or len(ns)!=1:raise CheckError('network shape')
            self.network=ns[0];bad=network_problems(self.network,self.release)
            self.add('docker.network','FAIL' if bad else 'PASS','Huidige netwerkconfig gecontroleerd; geen actieve internet/host-escapeproef.',{'differences':bad})
        except (OSError,CheckError,ValueError,TypeError):self.add('docker.network','FAIL','Netwerk ontbreekt/onleesbaar.')
        image_ok=True
        for key,image in self.ids.items():
            try:
                a=docker_json(['image','inspect',image]);d=a[0];cfg=d.get('Config') or {};labels=cfg.get('Labels') or {}
                good=d.get('Id')==image and d.get('Os')=='linux' and d.get('Architecture')=='amd64' and labels.get('io.cybertiel.managed')==self.release
                if key=='LLAMA_IMAGE':good=good and labels.get('org.opencontainers.image.revision')==self.baseline['llama_commit']
                image_ok=image_ok and good
                self.add('docker.image.'+key,'PASS' if good else 'FAIL','Lokale immutable image-ID/platform/releaselabel gecontroleerd.',{'id':image})
            except (OSError,CheckError,ValueError,TypeError,IndexError):image_ok=False;self.add('docker.image.'+key,'FAIL','Vastgelegde image ontbreekt/onleesbaar.')
        self.trusted_images=image_ok and bool(self.ids) and not any(x['status']=='FAIL' for x in self.rows if x['id'].startswith(('file.','config.','ready.','install.runtime')))
        for role in ('model','agent'):
            try:
                a=docker_json(['container','inspect','cybertiel-'+role]);c=a[0]
            except (OSError,CheckError,ValueError,TypeError,IndexError):
                self.add('docker.container.'+role,'FAIL' if role=='model' else 'NOT_APPLICABLE','Model ontbreekt.' if role=='model' else 'Geen actieve agentcontainer; normaal wanneer geen taak draait.');continue
            if role=='model':self.container=c
            bad=container_problems(c,role,self.release,self.ids['LLAMA_IMAGE' if role=='model' else 'AGENT_IMAGE'])
            self.add('docker.policy.'+role,'FAIL' if bad else 'PASS','Werkelijke containerconfig vergeleken met dit profiel.',{'differences':bad})
            state=c.get('State') or {};running=state.get('Running') is True
            self.add('docker.state.'+role,'PASS' if running and not state.get('OOMKilled') and not state.get('Restarting') and not state.get('Paused') else 'FAIL',
                     'Actuele processtatus, OOM en restarttoestand.',{'status':state.get('Status'),'running':running,'oom_killed':state.get('OOMKilled'),'exit_code':state.get('ExitCode'),'restart_count':c.get('RestartCount')})
            pid=state.get('Pid')
            if running and exact_int(pid,1,2**31-1):
                try:
                    before=read_system(f'/proc/{pid}/stat');text=read_system(f'/proc/{pid}/status').decode();armor=read_system(f'/proc/{pid}/attr/current').decode().strip()
                    after=read_system(f'/proc/{pid}/stat')
                    # starttime protects this observation against PID reuse.
                    first=before.rsplit(b')',1)[1].split()[19];last=after.rsplit(b')',1)[1].split()[19]
                    fields={l.split(':',1)[0]:l.split(':',1)[1].strip() for l in text.splitlines() if ':' in l}
                    good=first==last and fields.get('Seccomp')=='2' and fields.get('NoNewPrivs')=='1' and int(fields.get('CapEff','1'),16)==0 and armor=='docker-default (enforce)'
                    self.add('docker.live_sandbox.'+role,'PASS' if good else 'FAIL','Werkelijke init-processtatus gelezen; geen garantie tegen alle kernel-/containerlekken.',{'seccomp':fields.get('Seccomp'),'no_new_privs':fields.get('NoNewPrivs'),'effective_capabilities_zero':int(fields.get('CapEff','1'),16)==0,'apparmor':armor})
                except (OSError,CheckError,ValueError,IndexError):self.add('docker.live_sandbox.'+role,'UNTESTED','Live processtatus niet stabiel/leesbaar.')
    def runtime(self):
        if not self.args.runtime:
            self.add('runtime.inventory','UNTESTED','Geen tijdelijke runtimeproeven aangevraagd. Gebruik --runtime; installatie/config worden daarbij niet gewijzigd.');return
        if not self.trusted_images:
            self.add('runtime.inventory','UNTESTED','Runtimeproeven niet gestart: image-/configbaseline onvoldoende betrouwbaar.');return
        active=next((x for x in self.rows if x['id']=='docker.state.agent'),{})
        if active.get('status')=='PASS':
            self.add('runtime.inventory','UNTESTED','Agent draait al; geen extra buildproeven naast de taak. Stop de taak eerst.');return
        result=self.probe_container(TOOLCHAIN_PROBE.replace('@PI_VERSION_EXPECTED@',(self.baseline or {}).get('pi_version','1.0.0')),'none',with_config=False,timeout=300)
        if result is None:return
        if not isinstance(result,dict) or not isinstance(result.get('checks'),list):self.add('runtime.inventory','FAIL','Ongeldig runtimeantwoord.');return
        required={'node','npm','pi','gcc','gxx','clang','clangd','clang_tidy','clang_format','cmake','ninja','meson','gdb','valgrind','cppcheck','shellcheck','git','bear','python','pip','pytest','mypy','pwsh','mingw','cpp_runtime','cpp_negative_control','windows_x64_build_NOT_EXECUTION','pytest_runtime','powershell_linux_runtime','git_checkpoint'}
        entries=result['checks']
        if len(entries)!=len(required) or any(not isinstance(x,dict) or type(x.get('ok')) is not bool for x in entries) or {x.get('id') for x in entries}!=required:
            self.add('runtime.inventory','FAIL','Runtimeantwoord onvolledig, dubbel of ongeldig; geen gedeeltelijke rapportage als volledige test.');return
        for x in result['checks']:
            if not isinstance(x,dict) or not re.fullmatch(r'[A-Za-z0-9_.-]{1,80}',str(x.get('id',''))):continue
            self.add('runtime.'+x['id'],'PASS' if x.get('ok') is True else 'FAIL','Beperkte synthetische runtimeprobe, geen projecttest.',{'version':str(x.get('version',''))[:160]})
        tree=result.get('dependency_tree')
        if isinstance(tree,dict):
            r=assess_tree(tree);self.add('runtime.brace_expansion',r.pop('status'),'Werkelijke image-dependencytree vergeleken met advisories.',r)
        if self.release in ('2026-10-05.v17','2026-10-06.v18','2026-10-06.v19','2026-10-06.v20','2026-10-06.v21','2026-10-06.v22','2026-10-06.v23','2026-10-06.v24','2026-10-06.v25','2026-10-06.v25-r3'):
            proof=result.get('pi_lock_proof')
            errors=live_lock_problems(proof,self.baseline)
            self.add('runtime.pi_official_lock','FAIL' if errors else 'PASS','Actuele geïnstalleerde package-metadata door hash-gepinde lock gecontroleerd; geen algemene CVE-vrijheid.',{'problems':errors})
        if self.container and self.network and not container_problems(self.container,'model',self.release,self.ids['LLAMA_IMAGE']) and not network_problems(self.network,self.release):
            result=self.probe_container(API_PROBE,'cybertiel-internal',with_config=True,timeout=60)
            if isinstance(result,dict):
                self.add('runtime.model_health','PASS' if result.get('health_ok') is True else 'FAIL','GET /health vanuit de agentnetwerkroute; geen inference.')
                self.add('runtime.model_props','PASS' if result.get('props_ok') is True else 'FAIL','Geauthenticeerde GET /props: effectieve modelinstellingen; sleutel niet gerapporteerd.')
                self.add('runtime.model_identity','PASS' if result.get('model_ok') is True else 'FAIL','GET /v1/models bevat de beoogde alias.')
                self.add('runtime.pi_settings','PASS' if result.get('pi_settings_ok') is True else 'FAIL','Werkelijke Pi-entrypoint/SDK-configprobe in nieuwe tijdelijke HOME.')
        else:self.add('runtime.model_api','UNTESTED','Geen API-verkeer: model/netwerkbeleid niet bevestigd.')
    def probe_container(self,script,network,with_config,timeout):
        name='ct-inspect-'+os.urandom(8).hex();label='io.cybertiel.diagnostic='+name
        args=['run','--rm','--pull=never','--init','-i','--name',name,'--label',label,
              '--network',network,'--user','1000:1000','--cap-drop=ALL','--read-only',
              '--security-opt=no-new-privileges:true','--security-opt=seccomp=builtin','--security-opt=apparmor=docker-default',
              '--pids-limit','256','--memory','4g','--memory-swap','4g','--cpus','2','--ulimit','core=0:0',
              '--tmpfs','/tmp:rw,exec,nosuid,nodev,size=1g,mode=1777',
              '--tmpfs','/home/node:rw,nosuid,nodev,size=256m,mode=0700,uid=1000,gid=1000',
              '--tmpfs','/sessions:rw,nosuid,nodev,size=64m,mode=0700,uid=1000,gid=1000',
              '--workdir','/tmp','--env','HOME=/home/node','--env','PI_OFFLINE=1','--env','PYTHONDONTWRITEBYTECODE=1',
              '--env','POWERSHELL_TELEMETRY_OPTOUT=1','--env','DOTNET_CLI_TELEMETRY_OPTOUT=1']
        if with_config:args+=['--mount',f'type=bind,src={BASE}/config,dst=/opt/cybertiel/pi-config,readonly']
        args+=['--entrypoint','python3',self.ids['AGENT_IMAGE'],'-']
        q=None
        try:
            q=bounded_run(docker_args(args),timeout=timeout,stdin=script,limit=4*1024*1024)
            if q['rc']!=0 or q['reason']:
                self.add('runtime.probe.'+('api' if with_config else 'tools'),'FAIL','Tijdelijke controle mislukt/timeout; geen loginhoud opgenomen.',{'exit_code':q['rc'],'reason':q['reason']});return None
            return parse_json(q['stdout'])
        except (OSError,CheckError,ValueError):self.add('runtime.probe.'+('api' if with_config else 'tools'),'FAIL','Tijdelijke runtimecontrole leverde geen geldig rapport.');return None
        finally:
            # Stop/remove ONLY our random, positively labeled temporary container.
            # Killing the Docker CLI by itself is not a container-termination proof.
            try:
                a=docker_json(['container','inspect',name]);c=a[0]
                if (c.get('Config',{}).get('Labels') or {}).get('io.cybertiel.diagnostic')==name and re.fullmatch(r'[a-f0-9]{64}',str(c.get('Id',''))):
                    cleanup=bounded_run(docker_args(['rm','-f',c['Id']]),timeout=15)
                    if cleanup['rc']!=0 or cleanup['reason']:
                        self.add('runtime.cleanup.'+('api' if with_config else 'tools'),'FAIL','Eigen tijdelijke container kon niet aantoonbaar worden verwijderd.',{'temporary_name':name})
                else:
                    self.add('runtime.cleanup.'+('api' if with_config else 'tools'),'UNTESTED','Container-identiteit verschilt; geen verwijdering van mogelijk vreemde container.',{'temporary_name':name})
            except (OSError,CheckError,ValueError,TypeError,IndexError):
                # An absent --rm container is normal. Verify daemon accessibility
                # separately so an unavailable daemon is not called clean.
                try:
                    names=docker_json(['container','ls','-a','--filter','name=^/'+name+'$','--format','json'])
                    if names:self.add('runtime.cleanup.'+('api' if with_config else 'tools'),'UNTESTED','Tijdelijke containerstatus niet afgerond.',{'temporary_name':name})
                except (OSError,CheckError,ValueError,TypeError):
                    # ls --format json is JSONL; an empty string is valid absence.
                    r=bounded_run(docker_args(['container','ls','-aq','--filter','name=^/'+name+'$']),timeout=15,limit=4096)
                    if r['rc']!=0 or r['reason'] or r['stdout'].strip():
                        self.add('runtime.cleanup.'+('api' if with_config else 'tools'),'UNTESTED','Opruiming niet onafhankelijk bevestigd.',{'temporary_name':name})
    def conclusions(self):
        self.add('qualification.model_inference','UNTESTED','Geen modelantwoord/toolcalling-loop gegenereerd door dit script. Health/props zijn geen inferencebewijs.')
        self.add('qualification.user_project','UNTESTED','Jouw broncode, 500 bevindingen, EXE en Windows-VM niet uitgevoerd/gevalideerd.')
        self.add('qualification.security_updates','UNTESTED','Geen volledige actuele CVE-scan of online apt-refresh. Bekende advisories apart getoetst.')
        self.add('qualification.quotas','WARN','Geen onafhankelijke hard byte/inode-workspacequota bewezen; RAM/PID-grenzen vervangen dat niet.')
        self.add('qualification.performance','UNTESTED','262k-context en langdurige reparatierondes niet gebenchmarkt; een voorbeeld van de maker is geen Xeon-kwalificatie.')
        counts=dict(collections.Counter(x['status'] for x in self.rows))
        overall='ISSUES_FOUND' if counts.get('FAIL') else ('INCOMPLETE' if counts.get('UNTESTED') else 'CHECKED_NOT_PROJECT_QUALIFIED')
        return {'schema':'cybertiel-diagnostic/v1','checker':VERSION,'research_date':RESEARCH_DATE,
                'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':overall,
                'runtime_opt_in':self.args.runtime,'full_model_hash_opt_in':self.args.deep_model_hash,
                'checks':self.rows,'counts':counts,'facts':self.facts,'seconds':round(time.monotonic()-self.start,3),
                'writes':'only private report files; with --runtime additionally bounded temporary containers/synthetic files',
                'downloads_or_package_changes':False,'user_project_executed':False,'secrets_or_project_log_contents_included':False,
                'not_an_attestation_against_root_or_compromised_docker':True,
                'snapshot_not_continuous_attestation':True,'hash_deadline_checked_between_reads_not_against_kernel_io_hang':True}

# Deliberately fixed synthetic code, passed on stdin. No downloaded project code.
TOOLCHAIN_PROBE = r'''
import os,sys,json,subprocess,tempfile,pathlib,shutil,struct
checks=[]
def run(args,seconds=25):
 try:return subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=seconds)
 except Exception:return None
def add(i,ok,v=''):checks.append({'id':i,'ok':bool(ok),'version':v[:160]})
commands={'node':['node','--version'],'npm':['npm','--version'],'pi':['pi','--version'],
'gcc':['gcc','--version'],'gxx':['g++','--version'],'clang':['clang','--version'],
'clangd':['clangd','--version'],'clang_tidy':['clang-tidy','--version'],'clang_format':['clang-format','--version'],
'cmake':['cmake','--version'],'ninja':['ninja','--version'],'meson':['meson','--version'],
'gdb':['gdb','--version'],'valgrind':['valgrind','--version'],'cppcheck':['cppcheck','--version'],
'shellcheck':['shellcheck','--version'],'git':['git','--version'],'bear':['bear','--version'],
'python':['python3','--version'],'pip':['python3','-m','pip','--version'],
'pytest':['python3','-m','pytest','--version'],'mypy':['python3','-m','mypy','--version'],
'pwsh':['pwsh','-NoLogo','-NoProfile','-NonInteractive','-Command','$PSVersionTable.PSVersion.ToString()'],
'mingw':['x86_64-w64-mingw32-g++-posix','--version']}
for name,cmd in commands.items():
 p=run(cmd);out=(p.stdout or p.stderr).strip().splitlines()[0] if p and (p.stdout or p.stderr).strip() else ''
 ok=p is not None and p.returncode==0
 if name=='node':ok=ok and out=='v24.21.0'
 if name=='npm':ok=ok and out=='11.19.0'
 if name=='pi':ok=ok and out=='@PI_VERSION_EXPECTED@'
 if name=='pwsh':ok=ok and out=='7.6.6'
 add(name,ok,out)
with tempfile.TemporaryDirectory(prefix='ct-diagnostic-') as t:
 p=pathlib.Path(t);src=p/'check.cpp';src.write_text('#include <cstdio>\nint main(){if(19+23!=42)return 3;puts("CT_42");}\n')
 # C++ normal path and negative compiler control.
 b=run(['g++','-std=c++17',str(src),'-o',str(p/'check')]);r=run([str(p/'check')]) if b and b.returncode==0 else None
 add('cpp_runtime',bool(r and r.returncode==0 and r.stdout.strip()=='CT_42'))
 bad=p/'bad.cpp';bad.write_text('this is not C++;\n');b=run(['g++','-c',str(bad),'-o',str(p/'bad.o')]);add('cpp_negative_control',bool(b and b.returncode!=0))
 b=run(['x86_64-w64-mingw32-g++-posix',str(src),'-static','-o',str(p/'check.exe')],60)
 ok=False
 if b and b.returncode==0:
  raw=(p/'check.exe').read_bytes()
  if len(raw)>=64 and raw[:2]==b'MZ':
   off=struct.unpack_from('<I',raw,60)[0];ok=raw[off:off+6]==b'PE\0\0\x64\x86'
 add('windows_x64_build_NOT_EXECUTION',ok)
 py=p/'test_value.py';py.write_text('def test_value():\n    assert 19 + 23 == 42\n')
 r=run(['python3','-m','pytest','-q','-p','no:cacheprovider',str(py)]);add('pytest_runtime',bool(r and r.returncode==0))
 r=run(['pwsh','-NoLogo','-NoProfile','-NonInteractive','-Command','if ((19 + 23) -ne 42) {exit 1}; Write-Output CT_PS_OK']);add('powershell_linux_runtime',bool(r and r.returncode==0 and r.stdout.strip()=='CT_PS_OK'))
 git=p/'git';git.mkdir();r=run(['git','init','-q',str(git)]);(git/'note').write_text('synthetic\n')
 a=run(['git','-C',str(git),'add','note']);ident=run(['git','-C',str(git),'var','GIT_AUTHOR_IDENT']);c=run(['git','-C',str(git),'-c','commit.gpgsign=false','commit','-qm','synthetic'])
 add('git_checkpoint',bool(r and a and c and ident and r.returncode==a.returncode==c.returncode==ident.returncode==0 and ident.stdout.startswith('CyberTiel-Agent <cybertiel-agent@localhost>'))) 
q=run(['npm','--prefix','/opt/pi/install','ls','--omit=dev','--all','--json'],45)
try:tree=json.loads(q.stdout) if q else None
except Exception:tree=None
# Do not emit full tree or arbitrary command output (may contain config paths).
def small(d,depth=0):
 if not isinstance(d,dict) or depth>32:return {}
 out={}
 for k,v in (d.get('dependencies') or {}).items():
  if k=='brace-expansion':out[k]={'version':v.get('version','UNKNOWN')}
  else:
   s=small(v,depth+1)
   if s:out[k]=s
 return {'dependencies':out} if out else {}
proof=None
if '@PI_VERSION_EXPECTED@'=='1.0.3':
 z=run(['python3','/opt/cybertiel/verify-pi-lock.py','/opt/pi/install/package.json','/opt/pi/install/package-lock.json','--require-release-hashes','--installed-root','/opt/pi/install'],45)
 try:proof=json.loads(z.stdout) if z and z.returncode==0 else None
 except Exception:proof=None
print(json.dumps({'checks':checks,'dependency_tree':small(tree),'pi_lock_proof':proof}))
'''

API_PROBE = r'''
import json,urllib.request,subprocess
r={'health_ok':False,'props_ok':False,'model_ok':False,'pi_settings_ok':False}
try:
 d=json.load(open('/opt/cybertiel/pi-config/models.json'));key=d['providers']['cybertiel-local']['apiKey']
 op=urllib.request.build_opener(urllib.request.ProxyHandler({}))
 def get(path,auth=True):
  req=urllib.request.Request('http://cybertiel-model:8080'+path,headers={'Authorization':'Bearer '+key} if auth else {})
  with op.open(req,timeout=12) as f:
   raw=f.read(2*1024*1024+1)
   if len(raw)>2*1024*1024:raise ValueError('oversize')
   return json.loads(raw)
 r['health_ok']=get('/health',False).get('status')=='ok'
 p=get('/props');g=p.get('default_generation_settings') or {};q=g.get('params') or {}
 import math
 def number(k,v):
  x=q.get(k);return type(x) in (int,float) and math.isfinite(x) and abs(x-v)<1e-4
 r['props_ok']=type(g.get('n_ctx')) is int and g['n_ctx']==262144 and type(p.get('total_slots')) is int and p['total_slots']==1 and (p.get('modalities') or {}).get('vision') is True and all(type(q.get(k)) is int and q[k]==v for k,v in [('n_predict',-1),('max_tokens',-1),('top_k',20)]) and all(number(k,v) for k,v in [('temperature',.6),('top_p',.95),('min_p',0)])
 r['model_ok']=any(m.get('id')=='cybertiel-35b' for m in get('/v1/models').get('data',[]))
except Exception:pass
try:
 p=subprocess.run(['python3','/opt/cybertiel/agent-entrypoint.py','--ct-runtime-check'],capture_output=True,text=True,timeout=30)
 r['pi_settings_ok']=p.returncode==0 and 'CT_PI_SETTINGS_RUNTIME_OK' in p.stdout
except Exception:pass
print(json.dumps(r))
'''

def save_report(report,out=None):
    # Default output in an OS temporary directory outside the user workspace.
    # No overwrites; directory 0700, reports 0600, JSON encodes control chars.
    if out:
        parent=Path(out).absolute()
        if parent.is_symlink() or parent.resolve()!=parent or not parent.is_dir():raise CheckError('output parent must be an existing non-symlink directory')
        if str(parent)==str(DATA/'project') or str(parent).startswith(str(DATA/'project')+'/'):raise CheckError('do not write diagnostics into the project')
        if os.geteuid()==0 and (parent.stat().st_uid!=0 or stat.S_IMODE(parent.stat().st_mode)&0o022):raise CheckError('root output parent must be root-owned and private-writable')
        directory=Path(tempfile.mkdtemp(prefix='cybertiel-check-',dir=parent))
    else:directory=Path(tempfile.mkdtemp(prefix='cybertiel-check-',dir='/var/tmp'))
    directory.chmod(0o700)
    raw=(json.dumps(report,ensure_ascii=True,indent=2)+'\n').encode()
    lines=['CyberTiel controle '+VERSION,'Status: '+report['status'],
           'Dit rapport is GEEN bewijs van volledige projectcorrectheid.','']
    for row in report['checks']:lines.append(f"{row['status']:14} {row['id']}: {row['message']}")
    for name,content in [('report.json',raw),('report.txt',('\n'.join(lines)+'\n').encode())]:
        fd=os.open(directory/name,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
        with os.fdopen(fd,'wb') as f:f.write(content);f.flush();os.fsync(f.fileno())
    h=hashlib.sha256(raw).hexdigest()
    fd=os.open(directory/'SHA256SUMS',os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'w') as f:f.write(h+'  report.json\n')
    return directory

def main(argv=None):
    p=argparse.ArgumentParser(description='Controleer CyberTiel zonder installatie/updates. Rapport bevat geen sleutels, projectcode of debugloginhoud.')
    p.add_argument('--installer',help='Controleer ook dit geuploade .sh bestand; nooit uitvoeren.')
    p.add_argument('--deep-model-hash',action='store_true',help='Lees de volledige model/projectorbestanden en controleer SHA-256; veel schijf-I/O.')
    p.add_argument('--hash-timeout',type=int,default=3600,help='Maximum seconden per grote bestandshash (60..14400).')
    p.add_argument('--runtime',action='store_true',help='Expliciete opt-in: tijdelijke constrained containers met synthetische toolchain-/GET API-/Pi-settingsproeven; geen modelgeneratie/projectuitvoering.')
    p.add_argument('--output-parent',help='Bestaande veilige map voor een nieuw privaat rapportmapje; standaard /var/tmp.')
    args=p.parse_args(argv)
    if not 60<=args.hash_timeout<=14400:p.error('--hash-timeout moet 60..14400 zijn')
    if platform.system()!='Linux':print('Voer dit op de Linux-server uit, niet op je Mac.',file=sys.stderr);return 2
    os.umask(0o077);audit=Auditor(args)
    # Do not scan a mutating installation as though it were a stable snapshot.
    # v22 adds a persistent advisory lock on the already-existing /opt/cybertiel
    # directory inode. The checker can take this SH lock without creating any file,
    # so its default behavior remains read-only apart from its private report.
    fds=[]
    release_hint=None
    try:
        # Absent-path handshake for a fresh host. /opt already exists on the target
        # Ubuntu system and is never modified here. Holding SH prevents a conforming
        # first installer from creating BASE until this read-only scan is finished.
        parent_fd,_=open_managed_dir(Path('/opt'))
        try: fcntl.flock(parent_fd,fcntl.LOCK_SH|fcntl.LOCK_NB)
        except BaseException: os.close(parent_fd);raise
        fds.append(parent_fd)
        if BASE.exists() or os.path.lexists(BASE):
            base_fd,_=open_managed_dir(BASE)
            try: fcntl.flock(base_fd,fcntl.LOCK_SH|fcntl.LOCK_NB)
            except BaseException: os.close(base_fd);raise
            fds.append(base_fd)
        raw,_=read_managed(BASE/'.cybertiel-install-id',max_bytes=128)
        candidate=raw.decode('ascii','strict').strip()
        if candidate in BASELINES: release_hint=candidate
    except FileNotFoundError:
        # Fresh/uninstalled host: no CyberTiel installed-state success can be claimed.
        pass
    except (OSError,CheckError,UnicodeError):
        for fd in fds: os.close(fd)
        audit.add('snapshot.busy','UNTESTED','Installatie/agent actief of persistent coördinatiepad onveilig; controle niet tussendoor uitvoeren.')
        report=audit.conclusions();out=save_report(report,args.output_parent);print('Rapport: '+str(out/'report.json'));return 2
    locks=[Path('/run/cybertiel/operation.lock')]
    if release_hint not in ('2026-10-06.v18','2026-10-06.v19','2026-10-06.v20','2026-10-06.v21','2026-10-06.v22','2026-10-06.v23','2026-10-06.v24','2026-10-06.v25','2026-10-06.v25-r3'):
        locks.append(Path('/run/lock/cybertiel-operation.lock'))
    try:
        runtime_dir=Path('/run/cybertiel')
        if runtime_dir.exists() or os.path.lexists(runtime_dir):
            st=os.lstat(runtime_dir)
            if not stat.S_ISDIR(st.st_mode) or st.st_uid!=0 or stat.S_IMODE(st.st_mode)!=0o700:
                raise CheckError('unsafe current runtime lock directory')
        legacy_requires_runtime_lock=release_hint in ('2026-10-06.v18','2026-10-06.v19','2026-10-06.v20','2026-10-06.v21')
        current_lock_seen=False
        for lock in locks:
            if not os.path.lexists(lock): continue
            fd,_=open_managed(lock,max_bytes=4096)
            try: fcntl.flock(fd,fcntl.LOCK_SH|fcntl.LOCK_NB)
            except BaseException: os.close(fd);raise
            fds.append(fd)
            if lock==Path('/run/cybertiel/operation.lock'): current_lock_seen=True
        if legacy_requires_runtime_lock and not current_lock_seen:
            raise CheckError('legacy release has no persistent coordination protocol and runtime lock is absent')
    except (OSError,CheckError):
        for fd in fds: os.close(fd)
        audit.add('snapshot.busy','UNTESTED','Installatie/agent actief, legacy-lock ontbreekt of lock/runtime-lockmap onveilig; controle niet tussendoor uitvoeren.')
        report=audit.conclusions();out=save_report(report,args.output_parent);print('Rapport: '+str(out/'report.json'));return 2
    try:
        for id,fn in [('host',audit.host),('installed',audit.installed),('models',audit.models),('docker',audit.docker),('runtime',audit.runtime)]:
            audit.attempt('stage.'+id,fn,fail='UNTESTED')
        report=audit.conclusions();out=save_report(report,args.output_parent)
        print('\nSTATUS: '+report['status']);print('JSON: '+str(out/'report.json'));print('TEKST: '+str(out/'report.txt'))
        print('Stuur report.json terug; geen api-key, models.json, SSH-sleutel of projectlogs.')
        return 1 if report['counts'].get('FAIL') else 2 if report['counts'].get('UNTESTED') else 0
    finally:
        for fd in fds: os.close(fd)

if __name__=='__main__':
    try:sys.exit(main())
    except (OSError,CheckError,KeyboardInterrupt):
        print('CONTROLE ONVOLLEDIG: afgebroken of rapport niet veilig schrijfbaar. Geen succesclaim.',file=sys.stderr);sys.exit(2)

CYBERTIEL_DIAGNOSTIC_PY
