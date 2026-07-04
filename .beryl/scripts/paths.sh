#!/usr/bin/env bash

beryl_paths_init() {
  local source_path="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  local source_dir

  source_dir="$(cd "$(dirname "${source_path}")" && pwd)"

  case "${source_dir}" in
    */.beryl/scripts)
      BERYL_ROOT="$(cd "${source_dir}/.." && pwd)"
      ;;
    */.beryl/agent/scripts)
      BERYL_ROOT="$(cd "${source_dir}/../.." && pwd)"
      ;;
    */.beryl/githooks)
      BERYL_ROOT="$(cd "${source_dir}/.." && pwd)"
      ;;
    *)
      if [[ -d "${source_dir}/.beryl" ]]; then
        BERYL_ROOT="$(cd "${source_dir}/.beryl" && pwd)"
      elif [[ "$(basename "${source_dir}")" == ".beryl" ]]; then
        BERYL_ROOT="${source_dir}"
      else
        BERYL_ROOT="$(cd "${source_dir}/.." && pwd)"
      fi
      ;;
  esac

  if command -v git >/dev/null 2>&1 && git -C "${BERYL_ROOT}/.." rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT="$(git -C "${BERYL_ROOT}/.." rev-parse --show-toplevel)"
  else
    REPO_ROOT="$(cd "${BERYL_ROOT}/.." && pwd)"
  fi

  export BERYL_ROOT REPO_ROOT
}

beryl_path() {
  printf "%s/%s\n" "${BERYL_ROOT}" "${1#./}"
}

repo_path() {
  printf "%s/%s\n" "${REPO_ROOT}" "${1#./}"
}

beryl_paths_init
