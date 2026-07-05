#!/usr/bin/env bash
# safe-conf.sh — non-executing parser for repo-owned .conf files.
#
# .conf files used to be `source`d, which executes arbitrary shell from the
# repository (a code-execution channel for untrusted PRs in CI and at
# pre-commit). This parser assigns only an allowlisted set of variable names
# and treats every value as data. Supported syntax:
#
#   # full-line comments and blank lines
#   NAME="scalar value"
#   NAME=(
#     "item one"
#     "item two"
#   )
#   NAME=("inline" "items")
#   NAME=()
#
# Anything else — command substitution, expansions, stray shell — is a hard
# error, never executed.

sc_fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

sc_name_allowed() {
  local name="$1"
  shift
  local allowed
  for allowed in "$@"; do
    [[ "${name}" == "${allowed}" ]] && return 0
  done
  return 1
}

# sc_parse_tokens LINE CONF OUT_ARRAY_NAME
# Appends each token on LINE to the caller's array OUT_ARRAY_NAME.
# Tokens are double-quoted strings, single-quoted strings, or bare words made
# of safe characters. Quoted strings must not contain $, backtick, or
# backslash so no token can smuggle an expansion into later consumers.
sc_parse_tokens() {
  local rest="$1" conf="$2" out_var="$3" tok
  while [[ -n "${rest}" ]]; do
    rest="${rest#"${rest%%[![:space:]]*}"}"
    [[ -z "${rest}" ]] && break
    if [[ "${rest}" =~ ^\"([^\"\$\`\\]*)\"(.*)$ ]]; then
      tok="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]}"
    elif [[ "${rest}" =~ ^\'([^\']*)\'(.*)$ ]]; then
      tok="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]}"
    elif [[ "${rest}" =~ ^([A-Za-z0-9_@%+=:,./?*!-]+)(.*)$ ]]; then
      tok="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]}"
    else
      sc_fail "${conf}: unparseable token (only quoted strings and plain words are allowed): ${rest}"
    fi
    eval "${out_var}+=(\"\${tok}\")"
  done
}

# sc_load_conf CONF_FILE ALLOWED_NAME...
# Parses CONF_FILE and assigns each ALLOWED_NAME found in it (scalars via
# printf -v, arrays via reset-and-append). Unknown names, nested structures,
# and any executable construct fail closed.
sc_load_conf() {
  local conf="$1"
  shift
  [[ -f "${conf}" ]] || return 0

  local line name payload in_array=""
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ -n "${in_array}" ]]; then
      [[ "${line}" =~ ^[[:space:]]*(#.*)?$ ]] && continue
      if [[ "${line}" =~ ^[[:space:]]*\)[[:space:]]*$ ]]; then
        in_array=""
        continue
      fi
      sc_parse_tokens "${line}" "${conf}" "${in_array}"
      continue
    fi

    [[ "${line}" =~ ^[[:space:]]*(#.*)?$ ]] && continue

    if [[ "${line}" =~ ^([A-Z][A-Z0-9_]*)=\((.*)$ ]]; then
      name="${BASH_REMATCH[1]}"
      payload="${BASH_REMATCH[2]}"
      sc_name_allowed "${name}" "$@" || sc_fail "${conf}: variable not allowed here: ${name}"
      eval "${name}=()"
      if [[ "${payload}" =~ ^(.*)\)[[:space:]]*$ ]]; then
        sc_parse_tokens "${BASH_REMATCH[1]}" "${conf}" "${name}"
      elif [[ -z "${payload//[[:space:]]/}" ]]; then
        in_array="${name}"
      else
        sc_fail "${conf}: malformed array line: ${line}"
      fi
      continue
    fi

    if [[ "${line}" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
      name="${BASH_REMATCH[1]}"
      payload="${BASH_REMATCH[2]}"
      sc_name_allowed "${name}" "$@" || sc_fail "${conf}: variable not allowed here: ${name}"
      local -a sc_scalar_tokens=()
      sc_parse_tokens "${payload}" "${conf}" "sc_scalar_tokens"
      ((${#sc_scalar_tokens[@]} == 1)) || sc_fail "${conf}: expected exactly one value: ${line}"
      printf -v "${name}" '%s' "${sc_scalar_tokens[0]}"
      continue
    fi

    sc_fail "${conf}: unsupported line (this file is parsed as data, not executed): ${line}"
  done < "${conf}"

  [[ -z "${in_array}" ]] || sc_fail "${conf}: unterminated array: ${in_array}"
}
