#!/usr/bin/env bash
set -euo pipefail

raw_version="$(awk '$1 == "version:" { print $2; exit }' pubspec.yaml)"
if [[ -z "${raw_version}" ]]; then
  echo "pubspec.yaml 缺少 version 字段" >&2
  exit 1
fi
if [[ ! "${raw_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?$ ]]; then
  echo "pubspec.yaml 的 version 必须形如 2.0.8+1，实际为: ${raw_version}" >&2
  exit 1
fi

app_version="${raw_version%%+*}"
base_build="${raw_version#*+}"
if [[ "${base_build}" == "${raw_version}" ]]; then
  base_build=0
fi
base_build="${base_build%%[^0-9]*}"
if [[ -z "${base_build}" ]]; then
  base_build=0
fi

run_number="${GITHUB_RUN_NUMBER:-0}"
if [[ ! "${run_number}" =~ ^[0-9]+$ ]]; then
  echo "GITHUB_RUN_NUMBER 必须是整数，实际为: ${run_number}" >&2
  exit 1
fi
build_number=$((base_build + run_number))

display_version="${app_version}+${build_number}"
numeric_version="${app_version}.${build_number}"
commit_short="${GITHUB_SHA:0:7}"

{
  echo "app_version=${app_version}"
  echo "base_build=${base_build}"
  echo "build_number=${build_number}"
  echo "run_number=${run_number}"
  echo "display_version=${display_version}"
  echo "numeric_version=${numeric_version}"
  echo "commit_short=${commit_short}"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### 构建版本"
    echo
    echo "- 版本：\`${display_version}\`"
    echo "- 基础构建号：\`${base_build}\`"
    echo "- CI Run：\`${run_number}\`"
    echo "- Commit：\`${commit_short}\`"
  } >> "${GITHUB_STEP_SUMMARY}"
fi
