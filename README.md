# What the Duck? It's Zig!

The infamous [DuckDB quack extension](https://duckdb.org/community_extensions/extensions/quack.html) rewritten in C and built with Zig.

## Building the Extension

Install [Zig](https://ziglang.org) and [uv](https://docs.astral.sh/uv/). That's it. No other dependencies are required.

Now experience the power and simplicity of the [Zig Build System](https://ziglang.org/learn/build-system/) with these commands:

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

# Also install DuckDB C headers for development (to zig-out/include by default)
zig build -Dinstall-headers
```

The build output will look like this:

```
❯ tree zig-out
zig-out
├── linux_amd64
│   └── quack.duckdb_extension
├── linux_amd64_gcc4
│   └── quack.duckdb_extension
├── linux_arm64
│   └── quack.duckdb_extension
├── linux_arm64_gcc4
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

## Testing

Run the [SQL logic tests](https://duckdb.org/docs/dev/sqllogictest/intro.html) with `zig build test`.

```
❯ zig build test
[0/1] test/sql/quack.test
SUCCESS
```

_Note: Testing is currently broken for DuckDB 1.2.0 as the duckdb Python package is not yet available._

## Using the Extension

```
❯ duckdb -unsigned
v1.1.3 19864453f7
Enter ".help" for usage hints.
🟡◗ LOAD 'zig-out/osx_arm64/quack.duckdb_extension';
🟡◗ SELECT quack('Zig');
┌──────────────┐
│ quack('Zig') │
│   varchar    │
├──────────────┤
│ Quack Zig 🐥 │
└──────────────┘
```

## Advanced: Creating an Extension Repository

You can easily create your own [extension repository](https://duckdb.org/docs/extensions/working_with_extensions.html#creating-a-custom-repository) by providing a custom installation prefix.

Here's an example:

```
rm -rf repo

# Add more versions as needed
for version in 1.1.3 1.2.0; do
    zig build -Dduckdb-version=${version} --prefix repo/v${version} --release=fast
done

gzip repo/*/*/*.duckdb_extension
```

This will generate a repository with the following structure, ready to be uploaded to S3:

```
❯ tree repo
repo
├── v1.1.3
│   ├── linux_amd64
│   │   └── quack.duckdb_extension.gz
│   ├── linux_amd64_gcc4
│   │   └── quack.duckdb_extension.gz
│   ├── linux_arm64
│   │   └── quack.duckdb_extension.gz
│   ├── linux_arm64_gcc4
│   │   └── quack.duckdb_extension.gz
│   ├── osx_amd64
│   │   └── quack.duckdb_extension.gz
│   ├── osx_arm64
│   │   └── quack.duckdb_extension.gz
│   ├── windows_amd64
│   │   └── quack.duckdb_extension.gz
│   └── windows_arm64
│       └── quack.duckdb_extension.gz
└── v1.2.0
    ├── linux_amd64
    │   └── quack.duckdb_extension.gz
    ├── linux_amd64_gcc4
    │   └── quack.duckdb_extension.gz
    ├── linux_arm64
    │   └── quack.duckdb_extension.gz
    ├── linux_arm64_gcc4
    │   └── quack.duckdb_extension.gz
    ├── osx_amd64
    │   └── quack.duckdb_extension.gz
    ├── osx_arm64
    │   └── quack.duckdb_extension.gz
    ├── windows_amd64
    │   └── quack.duckdb_extension.gz
    └── windows_arm64
        └── quack.duckdb_extension.gz
```
