#!/usr/bin/env bash
set -euo pipefail

DUMP_PATH=""
ASSET_PATH=""

cleanup() {
  if [[ -n "${DUMP_PATH}" ]]; then
    rm -f -- "${DUMP_PATH}"
  fi
  if [[ -n "${ASSET_PATH}" ]]; then
    rm -f -- "${ASSET_PATH}"
  fi
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "${name} is required" >&2
    exit 1
  fi
}

get_or_create_release() {
  local release_tag="$1"
  local release_json

  release_json="$(curl -fsS \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/tags/${release_tag}" 2>/dev/null || true)"

  if jq -e '.id' >/dev/null 2>&1 <<<"${release_json}"; then
    printf '%s\n' "${release_json}"
    return
  fi

  local payload
  payload="$(jq -n --arg tag "${release_tag}" '{tag_name: $tag, name: $tag, prerelease: false}')"
  curl -fsS \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    --data "${payload}" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases"
}

delete_asset_if_exists() {
  local release_id="$1"
  local asset_name="$2"
  local assets_json
  local asset_id

  assets_json="$(curl -fsS \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/${release_id}/assets")"
  asset_id="$(jq -r --arg name "${asset_name}" '.[] | select(.name == $name) | .id' \
    <<<"${assets_json}" | head -n 1)"

  if [[ -n "${asset_id}" && "${asset_id}" != "null" ]]; then
    curl -fsS -X DELETE \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/assets/${asset_id}" \
      >/dev/null
  fi
}

upload_asset() {
  local upload_url="$1"
  local asset_path="$2"
  local asset_name="$3"
  local upload_endpoint="${upload_url%\{*}?name=${asset_name}"

  curl -fsS \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/zip" \
    --data-binary "@${asset_path}" \
    "${upload_endpoint}" \
    >/dev/null
}

main() {
  require_env GITHUB_REPOSITORY
  require_env GITHUB_TOKEN
  require_env RELEASE_ZIP_PASSWORD

  umask 077
  trap cleanup EXIT

  local output_dir="${OUTPUT_DIR:-/out}"
  local release_tag="${RELEASE_TAG:-$(date -u +%Y.%m.%d)}"
  local dump_namespaces="${DUMP_NAMESPACES:-0,4,6,8,10,12,14}"
  local asset_name="${RELEASE_ASSET_NAME:-mwarchiver-${release_tag}.zip}"
  DUMP_PATH="${output_dir}/52poke-${release_tag}.xml.gz"
  ASSET_PATH="${output_dir}/${asset_name}"

  mkdir -p "${output_dir}"

  cd /home/52poke/wiki
  php maintenance/run.php dumpBackup \
    --current \
    --namespaces="${dump_namespaces}" \
    --output="gzip:${DUMP_PATH}" \
    --quiet

  zip -j -P "${RELEASE_ZIP_PASSWORD}" "${ASSET_PATH}" "${DUMP_PATH}" >/dev/null
  rm -f -- "${DUMP_PATH}"
  DUMP_PATH=""

  local release_json
  local release_id
  local upload_url
  release_json="$(get_or_create_release "${release_tag}")"
  release_id="$(jq -er '.id' <<<"${release_json}")"
  upload_url="$(jq -er '.upload_url' <<<"${release_json}")"

  if [[ -n "${RELEASE_OVERWRITE:-}" ]]; then
    delete_asset_if_exists "${release_id}" "${asset_name}"
  fi

  upload_asset "${upload_url}" "${ASSET_PATH}" "${asset_name}"
}

main "$@"
