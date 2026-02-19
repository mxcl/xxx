# xxx

> SOMEBODY SET US UP THE BOMB \
> INSTALL ALL X

Securely install and keep updated all the `x` tools.

* npx
* uvx
* cargox
* brewx
* pkgx

Tools are installed from the *VENDOR* as root into `/usr/local`. It’s an
agentic world. Let’s be safe y’all.

> Go, Ruby? Yo yo yo. If someone would make a gox or gemx that actually worked
> then we’d do it. Get at it yo.

## Installation

```sh
curl -Ssf https://mxcl.dev/xxx/setup.sh |
  sudo bash -exo pipefail &&
  outdated | sh
```

We have deliberately split this out so all you security minded good boys can
feel less terrible about running a script from the internet.

1. `setup.sh` only installs our stubs and `outdated`. It does as little as possible.
2. `outdated` only outputs commands that it *would do*
3. So you then run it to install eg. node from the vendor etc.

Or if you hate `curl | sh` stuff then clone this repo and run `./install.sh`.
This route *does nothing*, it just outputs what it would do and tells you how
to then do it yourself.

The same applies to `outdated`—by default it has no side effects and just
prepares any available updates for you to review and apply.

## Outdated Script

Check for outdated installs and upgrade only what needs it by running:

```sh
$ outdated
```

- `outdated` has no side effects; it prints an apply script to stdout.
- Apply immediately with:
  ```sh
  outdated | sh
  ```
- Each managed item is checked for outdated status first.

## `/usr/local/bin`

Why? Because everything looks there. Not everything looks in
`/opt/homebrew/bin` or `~/.local/bin`.

We install a mix of stubs that delegate to `foox` tools and direct installs.

## Details

### Python

We use `uv` managed pythons. Because they do it properly. Unlike everyone
else.

### Rust

Your rust toolchain is managed via `rustup`. The stubs seemlessly delegate to
it and install it as required.

We do not mangle your shell environment with `source $HOME/.cargo/env`
instead the stubs dynamically inject that.
