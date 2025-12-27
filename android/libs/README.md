# Compiled libbox libraries

## Files

- `libbox.aar` (88MB) - for Android API 23+ (required)

## Compilation

Libraries are compiled from sources in `android/libbox/` using:
```bash
cd /tmp/sing-box-source
go run ./cmd/internal/build_libbox -target android
```

## Usage

In `android/build.gradle` added:
```gradle
implementation files('libs/libbox.aar')
```

## Recompilation

If you need to recompile the libraries:

1. Make sure you have installed:
   - Go 1.24+
   - Java 17, 21 or 23
   - Android NDK
   - gomobile from sagernet: `go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.10`

2. Запустите:
```bash
cd /tmp/sing-box-source
JAVA_HOME=/path/to/java17 go run ./cmd/internal/build_libbox -target android
```

3. Copy files:
```bash
cp /tmp/sing-box-source/libbox.aar android/libs/
```

## Compilation Date

- libbox.aar: December 25, 2024

