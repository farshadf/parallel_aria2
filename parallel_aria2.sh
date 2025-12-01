#!/usr/bin/env bash

# parallel_aria2
# Enable aria2c to download all files under a browsable HTTP/HTTPS URL
# without manually creating a URL list first.
#
# It:
#   1. Crawls the URL tree with wget (spider mode).
#   2. Builds an aria2c input file with URLs and per-file dir hints.
#   3. Runs aria2c to download everything in parallel,
#      preserving the remote folder structure under a local root directory.

show_help() {
    cat <<EOF
parallel_aria2

Usage:
  $(basename "$0") <username> <password> <URL> [aria2c-extra-args...]

Description:
  Enable aria2c to download every file under a browsable HTTP/HTTPS URL tree
  without manually creating a URL list first.

  The script:
    - Uses wget in spider mode to recursively discover files.
    - Generates an aria2c input file containing all URLs.
    - Preserves the remote folder structure locally by using per-URL dir hints.
    - Invokes aria2c for fast parallel downloads.

Positional arguments:
  username              HTTP basic auth username
  password              HTTP basic auth password
  URL                   Root HTTP/HTTPS URL to crawl (directory/folder)

Additional arguments:
  Any arguments after <URL> are passed directly to aria2c.

Environment variables:
  DOWNLOAD_LIST_FILE    Name/path of the aria2c input file.
                        Default: downloadlist.txt

  DOWNLOAD_ROOT_DIR     Local root directory where the remote folder
                        structure will be recreated.
                        Default: current working directory (.)

Default aria2c options used by this script:
  -x8   max 8 connections per server
  -j12  max 12 parallel downloads
  -c    continue downloads
  -m0   infinite retries
  -V    show console summary

Examples:
  # Basic usage
  $(basename "$0") myuser mypass "https://example.com/data/"

  # Pass extra options to aria2c (e.g. limit speed and retries)
  $(basename "$0") myuser mypass "https://example.com/data/" \\
      --max-tries=3 --max-overall-download-limit=2M

  # Change the URL list file and local download root
  DOWNLOAD_LIST_FILE=myfiles.txt \\
  DOWNLOAD_ROOT_DIR="/tmp/mirror" \\
  $(basename "$0") myuser mypass "https://example.com/data/"

EOF
}

# Handle --help / -h early
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    show_help
    exit 0
fi

# Basic argument checking
if [ $# -lt 3 ]; then
    echo "Error: missing required arguments." >&2
    echo "Usage: $(basename "$0") <username> <password> <URL> [aria2c-extra-args...]" >&2
    echo "Run with --help for more details." >&2
    exit 1
fi

username="$1"
password="$2"
URL="$3"
shift 3   # Remaining args are passed to aria2c
extra_aria_args=("$@")

# Decide whether to use HTTP auth
# Convention: username="-" and password="-" means "no auth"
if [ "$username" = "-" ] && [ "$password" = "-" ]; then
    wget_auth=()
    aria_auth=()
else
    wget_auth=(--user="$username" --password="$password")
    aria_auth=(--http-user="$username" --http-passwd="$password")
fi

# Files and directories
download_list="${DOWNLOAD_LIST_FILE:-downloadlist.txt}"
download_root="${DOWNLOAD_ROOT_DIR:-.}"

# Dependency checks
for cmd in wget aria2c; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command '$cmd' not found in PATH." >&2
        exit 1
    fi
done

# Normalize a URL into just its path (strip scheme, host, query)
normalize_url_path() {
    local u="$1"
    u="${u%%\?*}"        # strip query string
    u="${u#*://}"        # strip scheme
    u="${u#*/}"          # strip host
    echo "$u"
}

echo "[*] Building URL list from: $URL"
echo "[*] Output aria2c input file: $download_list"
echo "[*] Download root directory: $download_root"

# Ensure download_root exists
mkdir -p "$download_root" || {
    echo "Error: could not create download root directory '$download_root'." >&2
    exit 1
}

# Compute base path from starting URL
base_path="$(normalize_url_path "$URL")"
case "$base_path" in
    */) ;;
    *) base_path="$base_path/";;
esac

# Temporary file to hold raw URLs from wget
tmp_urls="$(mktemp -t parallel_aria2_urls.XXXXXX)"

# Crawl with wget in spider mode and collect URLs
wget \
  "${wget_auth[@]}" \
  -r -np -nH --cut-dirs=1 \
  --reject "index.html*" \
  --spider \
  "$URL" 2>&1 \
| awk '/^--/ {print $3}' \
| grep -E '^https?://' \
> "$tmp_urls"

if [ ! -s "$tmp_urls" ]; then
    echo "Error: no URLs were discovered. Check your URL, credentials, or wget options." >&2
    rm -f "$tmp_urls"
    exit 1
fi

# Build aria2c input file with per-URL dir hints
: > "$download_list"

while IFS= read -r url; do
    [ -n "$url" ] || continue

    # Normalize path
    url_path="$(normalize_url_path "$url")"

    # Compute relative path with respect to base_path
    rel="$url_path"
    case "$url_path" in
        "$base_path"*) rel="${url_path#$base_path}" ;;
    esac

    # Split into directory and filename
    rel_dir="$(dirname "$rel")"
    rel_file="$(basename "$rel")"

    # Protect against weird cases
    if [ -z "$rel_file" ] || [ "$rel_file" = "." ] || [ "$rel_file" = "/" ]; then
        continue
    fi

    # Build local directory path under download_root
    local_dir="$download_root"
    if [ "$rel_dir" != "." ] && [ -n "$rel_dir" ]; then
        local_dir="$download_root/$rel_dir"
    fi

    # Ensure directory exists (aria2c will also create it if needed, but this is safe)
    mkdir -p "$local_dir"

    # Write URL and dir hint for aria2c
    echo "$url" >> "$download_list"
    # aria2c input format: lines starting with space are options for the previous URL
    echo " dir=$local_dir" >> "$download_list"

done < "$tmp_urls"

rm -f "$tmp_urls"

if [ ! -s "$download_list" ]; then
    echo "Error: aria2c input file '$download_list' is empty after processing URLs." >&2
    exit 1
fi

echo "[*] Prepared $(grep -cE '^https?://' "$download_list") entries for aria2c."
echo "[*] Starting aria2c parallel download..."

aria2c \
  -x8 -j12 -c -m0 \
  "${aria_auth[@]}" \
  -V \
  -i "$download_list" \
  "${extra_aria_args[@]}"
