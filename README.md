# Miva Perl-Compatible Regular Expressions 2 (PCRE2)

PCRE2 bindings for Miva Merchant / Empresa as an external builtin library.

## Functions

| Function | Description |
|----------|-------------|
| `pcre2_regexp(pattern, string, options, output var)` | Match `pattern` against `string`. Returns `0` on no match, otherwise the **1-based** byte offset of the first match. |
| `pcre2_last_error()` | Last compile/match error message (empty after a clean no-match). |

### Options

| Flag | Meaning |
|------|---------|
| `i` | Case-insensitive |
| `g` | Find all matches |

### Output structure

On success, the `output` reference is filled as:

- `output:matches[n][c]` — capture `c` (1-based; `1` = full match) of match `n`
- `output:groups:name` — named captures from the **first** match only

## Usage

```mv
<MvASSIGN NAME="l.out" VALUE="">
<MvASSIGN NAME="l.match" VALUE="{ pcre2_regexp('^W[a-z]+', 'Welcome to the jungle', 'i', l.out) }">

<MvIF EXPR="{ l.match }">
  Matched at offset <MvEVAL EXPR="{ l.match }">:
  <MvEVAL EXPR="{ l.out:matches[1][1] }">
</MvIF>
```

Named groups:

```mv
<MvASSIGN NAME="l.out" VALUE="">
<MvASSIGN NAME="l.match" VALUE="{ pcre2_regexp('(?<user>\\w+)@(?<host>[\\w.]+)', 'a@b.com', '', l.out) }">

<MvEVAL EXPR="{ l.out:groups:user }">   <!-- a -->
<MvEVAL EXPR="{ l.out:groups:host }">   <!-- b.com -->
```

## Build & test

Requires a local Miva VM (`mivavm`) and compiler (`mvc`). Defaults:

```makefile
VM  ?= /Users/pasha/mivavm
MVC ?= /Users/pasha/mvc
```

Override as needed: `make test VM=/path/to/mivavm MVC=/path/to/mvc`.

```bash
git submodule update --init --recursive
make local          # build bin/darwin-x86_64/miva_pcre2.so (builds PCRE2 if needed)
make install        # copy into VM + mvc builtins
make test           # install, compile test/test.mv, run via mivavm
```

Other platforms: `make darwin-arm64`, `make linux-x86_64`, `make help`.

## License

Apache-2.0. PCRE2 is included as a submodule under its own license (see `include/pcre2/LICENCE.md`).
