[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
# parallel_aria2

`parallel_aria2` is a small command-line helper that **enables `aria2c` to download every file under a browsable HTTP/HTTPS URL tree** without you having to manually build a URL list first.

It works by:

1. Crawling the remote directory with `wget` in spider mode.
2. Automatically generating an `aria2c` input file from the discovered URLs.
3. Preserving the remote folder structure under a local output directory.
4. Feeding that list into `aria2c` for fast, parallel downloads.

---

## Features

- Turn a directory-style HTTP/HTTPS URL into a full `aria2c` download job.
- Automatically discover all files reachable via `wget` recursion.
- Preserve the remote subdirectory structure under a local download root.
- Supports both HTTP Basic Authentication and anonymous (no-auth) access.
- Any extra CLI arguments after the URL are passed directly to `aria2c`.
- Simple, self-contained Bash script with built-in `--help`.

---

## Requirements

- Unix-like environment (Linux, macOS, WSL, etc.)
- Bash
- [`wget`](https://www.gnu.org/software/wget/)
- [`aria2c`](https://aria2.github.io/)

Check that both tools are installed and available in your `PATH`:

```bash
wget --version
aria2c --version
```

---

## Installation

Clone the repository and make the script executable:

```bash
git clone https://github.com/<your-username>/parallel_aria2.git
cd parallel_aria2
chmod +x parallel_aria2
```

Optionally, move it somewhere on your `PATH`:

```bash
sudo mv parallel_aria2 /usr/local/bin/
```

---

## Usage

Basic syntax:

```bash
parallel_aria2 <username> <password> <URL> [aria2c-extra-args...]
```

- `username` – HTTP basic auth username, or `-` for anonymous mode.
- `password` – HTTP basic auth password, or `-` for anonymous mode.
- `URL` – Root HTTP/HTTPS URL to crawl (directory/folder listing).
- `aria2c-extra-args` – Any additional options you want to pass directly to `aria2c`.

To see help:

```bash
parallel_aria2 --help
```

---

## Authentication modes

### 1. Authenticated access (HTTP Basic Auth)

If your server requires HTTP Basic Authentication, pass your credentials as usual:

```bash
parallel_aria2 myuser mypass "https://secure.example.com/data/"
```

The script will:

- Provide `--user` / `--password` to `wget`, and
- Provide `--http-user` / `--http-passwd` to `aria2c`.

### 2. Anonymous / public access (no auth)

If the URL is anonymously accessible and you **do not** want to send any Authorization headers at all, use `-` for both username and password:

```bash
parallel_aria2 "-" "-" "https://example.com/public/"
```

In this mode, the script **omits all auth options** for both `wget` and `aria2c`. The server must allow public access to the content under the given URL.

You can still pass additional options to `aria2c`:

```bash
parallel_aria2 "-" "-" "https://example.com/public/" \
  --max-tries=3 \
  --max-overall-download-limit=5M
```

---

## Examples

### 1. Simple authenticated download

```bash
parallel_aria2 myuser mypass "https://example.com/data/"
```

This will:

1. Crawl `https://example.com/data/` recursively with `wget`.
2. Generate an `aria2c` input file (default: `downloadlist.txt`) that includes directory hints.
3. Download all discovered files in parallel, recreating the remote folder structure locally.

### 2. Anonymous download from a public URL

```bash
parallel_aria2 "-" "-" "https://example.com/public/data/"
```

No authentication headers will be sent; all files under `https://example.com/public/data/` that `wget` can see will be downloaded with `aria2c` using parallel transfers.

### 3. Limit overall download speed and number of tries

```bash
parallel_aria2 myuser mypass "https://example.com/data/" \
  --max-tries=3 \
  --max-overall-download-limit=2M
```

All arguments after the URL are passed straight to `aria2c`.

### 4. Use a custom URL list filename and output root directory

```bash
DOWNLOAD_LIST_FILE=myfiles.txt \
DOWNLOAD_ROOT_DIR="downloads" \
parallel_aria2 myuser mypass "https://example.com/data/"
```

- Discovered URLs will be written to `myfiles.txt`.
- All files will be downloaded under the `downloads/` directory, keeping the remote subdirectory layout.

---

## Default behavior

### `wget` (URL discovery)

`parallel_aria2` uses `wget` in spider mode to crawl the URL tree:

- `-r` – recursive
- `-np` – no parent
- `-nH` – disable host-prefixed directories
- `--cut-dirs=1` – drop one leading directory component (tune as needed)
- `--reject "index.html*"` – skip index pages
- `--spider` – check only, do not download files

The script parses `wget`'s output to extract the discovered URLs.

### `aria2c` (downloading)

The script feeds an **aria2-compatible input file** to `aria2c` and uses these default options:

- `-x8` – up to 8 connections per server
- `-j12` – up to 12 parallel downloads
- `-c` – continue partial downloads
- `-m0` – infinite retries
- `-V` – show console summary
- `--http-user`, `--http-passwd` – only when you provide real credentials (not `-`/`-`)
- `-i <download list>` – input file containing URLs and per-URL options

You can override or extend `aria2c` behavior by passing extra command-line arguments after the URL.

---

## Folder structure preservation

A key goal of `parallel_aria2` is to **keep the same folder layout locally as you have under the starting URL**.

Internally, the script:

1. Normalizes the path portion of the starting `URL`.
2. Normalizes the path of each discovered URL.
3. Computes a relative path for each file (remote path minus the base path).
4. Splits that relative path into:
   - a directory component, and
   - a file name.
5. Writes each URL to the input file along with a `dir=...` directive for `aria2c`, so that:
   - Subdirectories are recreated under the chosen download root.
   - Files appear in the correct relative folders.

If you specify `DOWNLOAD_ROOT_DIR`, that directory becomes the top-level location under which the entire mirrored tree is created.

---

## Environment variables

- `DOWNLOAD_LIST_FILE`  
  Name/path of the generated aria2c input file.  
  Default: `downloadlist.txt`

- `DOWNLOAD_ROOT_DIR`  
  Root directory under which the remote folder structure is recreated.  
  Default: current working directory (`.`)

Example:

```bash
DOWNLOAD_LIST_FILE="aria_downloads.txt" \
DOWNLOAD_ROOT_DIR="/data/mirror" \
parallel_aria2 "-" "-" "https://example.com/public/data/"
```

---

## Notes and limitations

- This script assumes:
  - Either HTTP Basic Authentication (username/password) **or** completely anonymous access.
  - Directory-style listings that `wget` can parse and crawl.
- It does **not**:
  - Handle complex web apps that require JavaScript or dynamic navigation.
  - Manage cookies or more advanced authentication flows out of the box.
- URL discovery is controlled by the `wget` options inside the script. If your server layout is different, you may need to adjust:
  - `--cut-dirs`
  - `--reject` patterns
  - Recursion depth (`-l`)

---

## License

MIT License

Copyright (c) 2025 Farshad Farshidfar <farshidfar@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the “Software”), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice (including the next
paragraph) shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
