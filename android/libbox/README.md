# libbox - library for working with sing-box

## Description

This folder contains the source code of the `libbox` library from the [sing-box](https://github.com/SagerNet/sing-box) repository.

## Source

Copied from: `/tmp/sing-box-source/experimental/libbox`

Original repository: https://github.com/SagerNet/sing-box

## What is this?

`libbox` is a Go library that provides an API for working with sing-box from Android/Kotlin through JNI (Java Native Interface).

## Compilation

To compile into an Android library (.aar), you need to:

1. Install Go and gomobile:
```bash
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init
```

2. Compile the library:
```bash
cd android/libbox
gomobile bind -target android -o libbox.aar github.com/SagerNet/sing-box/experimental/libbox
```

3. Add to `android/build.gradle`:
```gradle
dependencies {
    implementation files('libs/libbox.aar')
}
```

## Structure

- `command.go` - commands for managing sing-box
- `command_client.go` - client for executing commands
- `config.go` - configuration handling
- `dns.go` - DNS functionality
- `log.go` - logging
- `memory.go` - memory management
- `monitor.go` - monitoring
- `pprof.go` - profiling
- And other files...

## Usage

After compilation, the library will be available as `io.nekohasekai.libbox.*` in Kotlin code.

## Note

These sources need to be compiled using `gomobile` to obtain the Android library (.aar file).
