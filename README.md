# mojo-pkg

A package manager CLI for Mojo, written in pure Mojo.

## Installation

### Supported platforms

| Platform | Archive |
|----------|---------|
| Linux x86_64 | `mojo-pkg-linux-64.tar.gz` |
| macOS ARM64 (Apple Silicon) | `mojo-pkg-osx-arm64.tar.gz` |

### Quick install (Linux and macOS)

```bash
curl -fsSL https://raw.githubusercontent.com/Mosaad-M/mojo-pkg/main/scripts/install.sh | bash
```

The script auto-detects your platform and downloads the correct binary.

Some networks block `raw.githubusercontent.com`. If the command above fails with a TLS
or connection error, fetch the same script through the GitHub API:

```bash
curl -fsSL -H "Accept: application/vnd.github.raw" \
  https://api.github.com/repos/Mosaad-M/mojo-pkg/contents/scripts/install.sh | bash
```

### Manual

Download from [GitHub Releases](https://github.com/Mosaad-M/mojo-pkg/releases/latest), extract, and add `~/.mojo/bin` to your PATH.

Verify the download (Linux):

```bash
sha256sum -c mojo-pkg-linux-64.tar.gz.sha256
```

Verify the download (macOS):

```bash
shasum -a 256 -c mojo-pkg-osx-arm64.tar.gz.sha256
```

> **Note:** The release tarball contains two files: `mojo-pkg` (a shell wrapper) and `mojo-pkg-bin` (the compiled binary). The wrapper automatically sets `LD_LIBRARY_PATH` (Linux) or `DYLD_LIBRARY_PATH` (macOS) to the Mojo runtime libs — you don't need to set it manually.

## Build from Source

### Prerequisites

- [pixi](https://pixi.sh) for environment management
- Mojo ≥ 0.26.1 (via pixi)
- The [tls](https://github.com/Mosaad-M/tls) repo cloned as a sibling directory. The build and test scripts check for `../tls_pure` then `../tls` automatically, so either name works:
  ```bash
  git clone https://github.com/Mosaad-M/tls.git ../tls_pure  # or ../tls
  ```
  Alternatively, set `TLS_PURE=/path/to/your/clone` to point anywhere.

```bash
pixi run build
# Installs to ~/.mojo/bin/mojo-pkg
export PATH="$HOME/.mojo/bin:$PATH"
```

## Usage

```bash
# Install all dependencies declared in mojoproject.toml
mojo-pkg install

# Add a dependency
mojo-pkg add tls Mosaad-M/tls ">=1.0.0"

# Print compiler flags for use in build scripts
mojo $(mojo-pkg flags)

# Search the registry
mojo-pkg search tls

# List installed packages
mojo-pkg list
```

## Version constraints and resolution

Constraints in `mojoproject.toml` are one or more comparators joined by commas, all of
which must hold: `>=1.2.0`, `>1.2.0`, `<=1.2.0`, `<2.0.0`, `=1.2.0`, `^1.2.0`, or a
range such as `>=1.0.0,<2.0.0`.

```toml
[dependencies]
requests = { git = "Mosaad-M/requests", version = ">=1.0.0" }
json     = { git = "Mosaad-M/json",     version = ">=1.0.0,<2.0.0" }
```

`install` (without a `mojo.lock`), `update`, `add` and `remove` resolve the whole
dependency graph. Packages declare which versions of their own dependencies they work
with in the registry (`dep_constraints`), and the resolver picks the newest versions
that satisfy every constraint, falling back to older versions when needed. For
example, pinning `json = "=1.1.0"` alongside `requests = ">=1.0.0"` selects the newest
requests release that still works with json 1.x. If no combination exists, the error
lists the conflicting constraints and where each came from. An existing `mojo.lock` is
installed as-is.

The registry is read from `raw.githubusercontent.com`. If that host is unreachable
(some networks filter it), mojo-pkg fetches the same index files from GitHub's contents
API instead, with no configuration. Unauthenticated API requests are limited to 60 per
hour; set `GITHUB_TOKEN` to raise the limit.

## Running Tests

```bash
pixi run test
```

Each module has its own test task:

```bash
pixi run test-toml
pixi run test-manifest
pixi run test-semver
pixi run test-validate
pixi run test-lockfile
pixi run test-flags
pixi run test-json
pixi run test-url
pixi run test-resolver
```

`scripts/e2e_resolve.sh <mojo-pkg binary>` resolves sample projects against the live
registry (run in CI after building the binary).

## Project Structure

```
src/
  main.mojo       — CLI entry point
  manifest.mojo   — mojoproject.toml parser/writer
  toml.mojo       — TOML subset parser
  lockfile.mojo   — mojo.lock read/write
  resolver.mojo   — semver dependency resolver
  registry.mojo   — package registry HTTP client
  installer.mojo  — tarball download + install
  flags.mojo      — compiler flag generation
  validate.mojo   — input validation
  fs.mojo         — file system helpers
  json.mojo       — JSON parser
  url.mojo        — URL parser
  http_client.mojo — HTTP/HTTPS client (wraps tls_pure)
tests/
  test_toml.mojo
  test_manifest.mojo
  test_semver.mojo
  test_validate.mojo
  test_lockfile.mojo
  test_flags.mojo
  test_json.mojo
  test_url.mojo
```

## License

MIT
