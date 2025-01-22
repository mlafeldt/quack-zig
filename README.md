# What the Duck? It's Zig!

The infamous [DuckDB quack extension](https://duckdb.org/community_extensions/extensions/quack.html) rewritten in C and built with Zig.

## Building the Extension

[Install Zig](https://ziglang.org/learn/getting-started/). That's it. No other dependencies are required.

Now experience the power of the [Zig Build System](https://ziglang.org/learn/build-system/) with these commands:

```
# Build extension for all platforms (Linux, macOS, Windows)
zig build

# Only build for a specific platform
zig build -Dplatform=linux_amd64

# Build for multiple platforms
zig build -Dplatform=linux_arm64 -Dplatform=osx_arm64 -Dplatform=windows_arm64

# Build for a specific DuckDB version
zig build -Dduckdb-version=1.1.2

# Optimize for performance
zig build --release=fast

# Optimize for binary size
zig build --release=small

# Also install DuckDB headers for development
zig build -Dinstall-headers
```

The build output will look like this:

```
❯ tree zig-out
zig-out
├── linux_amd64
│   └── quack.duckdb_extension
├── linux_arm64
│   └── quack.duckdb_extension
├── osx_amd64
│   └── quack.duckdb_extension
├── osx_arm64
│   └── quack.duckdb_extension
├── windows_amd64
│   └── quack.duckdb_extension
└── windows_arm64
    └── quack.duckdb_extension
```

See `zig build --help` for more options.

## Using the Extension

```
❯ duckdb -unsigned
v1.1.3 19864453f7
Enter ".help" for usage hints.
🟡◗ LOAD 'zig-out/osx_arm64/quack.duckdb_extension';
🟡◗ SELECT quack('||| Arena');
┌────────────────────┐
│ quack('||| Arena') │
│      varchar       │
├────────────────────┤
│ Quack ||| Arena 🐥 │
└────────────────────┘
```

## Advanced: Creating an Extension Repository

By providing an installation prefix, you can easily create a [custom extension repository](https://duckdb.org/docs/extensions/working_with_extensions.html#creating-a-custom-repository).

Here's an example:

```
zig build -Dduckdb-version=1.1.2 --prefix repo/v1.1.2 --release=fast

zig build -Dduckdb-version=1.1.3 --prefix repo/v1.1.3 --release=fast
```

This will generate a repository with the following structure, ready to be uploaded to S3:

```
❯ tree -d repo
repo
├── v1.1.2
│   ├── linux_amd64
│   ├── linux_arm64
│   ├── osx_amd64
│   ├── osx_arm64
│   ├── windows_amd64
│   └── windows_arm64
└── v1.1.3
    ├── linux_amd64
    ├── linux_arm64
    ├── osx_amd64
    ├── osx_arm64
    ├── windows_amd64
    └── windows_arm64
```
