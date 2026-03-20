# mojo-pkg

A package manager CLI for Mojo, written in pure Mojo.

## Installation

### Quick install (Linux x86_64)

```bash
curl -fsSL https://raw.githubusercontent.com/Mosaad-M/mojo-pkg/main/scripts/install.sh | bash
```

### Manual

Download from [GitHub Releases](https://github.com/Mosaad-M/mojo-pkg/releases/latest), extract, and add `~/.mojo/bin` to your PATH.

Verify the download:

```bash
sha256sum -c mojo-pkg-linux-64.tar.gz.sha256
```

## Build from Source

### Prerequisites

- [pixi](https://pixi.sh) for environment management
- Mojo ≥ 0.26.1 (via pixi)
- A sibling `tls_pure/` directory at `../tls_pure` — clone with `git clone https://github.com/Mosaad-M/tls.git ../tls_pure` (or set `TLS_PURE` env var to a custom path)

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
```

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
