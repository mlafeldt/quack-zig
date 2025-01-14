# What the Duck? It's Zig!

The infamous [DuckDB quack extension](https://duckdb.org/community_extensions/extensions/quack.html) rewritten in C and built with Zig.

## Building

[Install Zig](https://ziglang.org/learn/getting-started/). That's it, no other dependencies are required.

Now experience the power of the [Zig Build System](https://ziglang.org/learn/build-system/) with these commands:

```
# Build extension for all platforms (Linux, macOS, Windows)
zig build

# Only build for a specific platform
zig build -Dplatform=linux_amd64

# Build for multiple platforms
zig build -Dplatform=linux_arm64 -Dplatform=osx_arm64 -Dplatform=windows_arm64

# Optimize for performance
zig build --release=fast

# Optimize for binary size
zig build --release=small

# Also install DuckDB library and headers
zig build -Dinstall-lib
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
