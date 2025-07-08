# What the Duck? It's Zig! ⚡️

The infamous [DuckDB quack extension](https://duckdb.org/community_extensions/extensions/quack.html) rewritten in C and built with Zig.

Proof that you can develop DuckDB extensions without drowning in boilerplate.

## Building the Extension

Install [Zig](https://ziglang.org) and [uv](https://docs.astral.sh/uv/). That's it. No other dependencies are required.

Now experience the power and simplicity of the [Zig Build System](https://ziglang.org/learn/build-system/) with these commands:

```shell
# Build the extension for all supported DuckDB versions and platforms (Linux, macOS, Windows)
zig build

# Build for a list of DuckDB versions
zig build -Dduckdb-version=1.1.3 -Dduckdb-version=1.2.0

# Build for a list of platforms
zig build -Dplatform=linux_arm64 -Dplatform=osx_arm64 -Dplatform=windows_arm64

# Build for a specific DuckDB version and platform
zig build -Dduckdb-version=1.1.3 -Dplatform=linux_amd64

# Optimize for performance
zig build --release=fast

# Optimize for binary size
zig build --release=small

# Also install DuckDB C headers for development
zig build -Dinstall-headers
```

The build output in `zig-out` will look like this:

```
❯ tree zig-out
zig-out
├── v1.1.0
│   ├── linux_amd64
│   │   └── quack.duckdb_extension
│   ├── linux_amd64_gcc4
│   │   └── quack.duckdb_extension
│   ├── linux_arm64
│   │   └── quack.duckdb_extension
│   ├── linux_arm64_gcc4
│   │   └── quack.duckdb_extension
│   ├── osx_amd64
│   │   └── quack.duckdb_extension
│   ├── osx_arm64
│   │   └── quack.duckdb_extension
│   ├── windows_amd64
│   │   └── quack.duckdb_extension
│   └── windows_arm64
│       └── quack.duckdb_extension
├── v1.1.1
│   ├── linux_amd64
│   │   └── quack.duckdb_extension
│   ├── linux_amd64_gcc4
│   │   └── quack.duckdb_extension
│   ├── linux_arm64
│   │   └── quack.duckdb_extension
│   ├── linux_arm64_gcc4
│   │   └── quack.duckdb_extension
│   ├── osx_amd64
│   │   └── quack.duckdb_extension
│   ├── osx_arm64
│   │   └── quack.duckdb_extension
│   ├── windows_amd64
│   │   └── quack.duckdb_extension
│   └── windows_arm64
│       └── quack.duckdb_extension
├── ...
```

See `zig build --help` for more options.

## Testing

Run the [SQL logic tests](https://duckdb.org/docs/dev/sqllogictest/intro.html) with `zig build test`.

```
❯ zig build test --summary new
[1/1] test/sql/quack.test
SUCCESS
[1/1] test/sql/quack.test
SUCCESS
[1/1] test/sql/quack.test
SUCCESS
[1/1] test/sql/quack.test
SUCCESS
[1/1] test/sql/quack.test
SUCCESS
[1/1] test/sql/quack.test
SUCCESS
[1/1] test/sql/quack.test
SUCCESS
[1/1] test/sql/quack.test
SUCCESS
[1/1] test/sql/quack.test
SUCCESS
[1/1] test/sql/quack.test
SUCCESS
Build Summary: 31/31 steps succeeded
test success
├─ sqllogictest v1.1.0 osx_arm64 success 91ms MaxRSS:46M
├─ sqllogictest v1.1.1 osx_arm64 success 91ms MaxRSS:46M
├─ sqllogictest v1.1.2 osx_arm64 success 92ms MaxRSS:45M
├─ sqllogictest v1.1.3 osx_arm64 success 92ms MaxRSS:46M
├─ sqllogictest v1.2.0 osx_arm64 success 109ms MaxRSS:47M
├─ sqllogictest v1.2.1 osx_arm64 success 99ms MaxRSS:47M
├─ sqllogictest v1.2.2 osx_arm64 success 101ms MaxRSS:48M
├─ sqllogictest v1.3.0 osx_arm64 success 100ms MaxRSS:48M
├─ sqllogictest v1.3.1 osx_arm64 success 101ms MaxRSS:48M
└─ sqllogictest v1.3.2 osx_arm64 success 101ms MaxRSS:48M
```

You can also pass `-Dduckdb-version` to test against a specific DuckDB version, or use `-Dplatform` to select a different native platform, e.g. `linux_amd64_gcc4` instead of `linux_amd64`.

## Using the Extension

```
❯ duckdb -unsigned
DuckDB v1.3.2 (Ossivalis) 0b83e5d2f6
Enter ".help" for usage hints.
🟡◗ LOAD 'zig-out/v1.3.2/osx_arm64/quack.duckdb_extension';
🟡◗ SELECT quack('Zig');
┌──────────────┐
│ quack('Zig') │
│   varchar    │
├──────────────┤
│ Quack Zig 🐥 │
└──────────────┘
```

## Creating an Extension Repository

You can easily create your own [extension repository](https://duckdb.org/docs/extensions/working_with_extensions.html#creating-a-custom-repository). In fact, `zig build` already does this for you by default! However, you might also want to write files to a different directory and compress them. Here's how:

```shell
rm -rf repo

zig build --prefix repo --release=fast

gzip repo/*/*/*.duckdb_extension
```

This will generate a repository that is ready to be uploaded to S3 with a tool like [rclone](https://rclone.org).

## License

Licensed under the [MIT License](LICENSE).

Feel free to use this code as a starting point for your own DuckDB extensions. 🐤
