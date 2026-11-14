# OpenBurn

OpenBurn is a lightweight optical disc suite for creating ISO images, listing
optical drives, burning images, and checking image media. It includes a
command-line interface and a native macOS GUI.

## Requirements

- CMake 3.16 or newer
- A C++20 compiler
- `xorriso` installed and available on `PATH` for the command-line interface
- macOS and Xcode command-line tools for the native GUI target

For example, install xorriso with `brew install xorriso` on macOS or
`sudo apt install xorriso` on Debian/Ubuntu. The GUI uses macOS's built-in
`hdiutil` utility instead.

## Build

```sh
cmake -S . -B build
cmake --build build
```

On macOS, launch the GUI with:

```sh
open build/openburn-gui.app
```

The macOS installer package is available from the
[latest GitHub release](https://github.com/thomaswales26-hash/OpenBurn/releases/latest).

## Use

```sh
openburn devices
openburn image ./disc-files ./disc.iso
openburn verify ./disc.iso
openburn burn ./disc.iso /dev/disk4
```

The `burn` command asks for confirmation because writing to optical media may
be irreversible. Pass `--yes` to skip the prompt when running it
intentionally in a script. Select the correct device for your system;
`openburn devices` lists drives recognized by xorriso. The macOS GUI has
buttons for creating, verifying, and burning images, plus a drive scan. macOS
may detect a USB optical drive but report it as unsupported; OpenBurn displays
the system's support status and cannot override that limitation.
