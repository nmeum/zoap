# zoap

A toy parser for the [CoAP][coap rfc] message format.

## Status

This is just intended a small experiment with the
[Zig programming language][zig web]. The goal isn't creating a complete
standard-compliant implementation of CoAP in Zig. However, this toy
implementation is used presently in [zig-riscv-embedded][zig-riscv github].
This code is known to compile with Zig `0.8.1`.

## Installation

See [How do I use packages?](https://github.com/ziglang/zig/wiki/FAQ#how-do-i-use-packages).

## Usage

See [zig-riscv-embedded][zig-riscv github] for a usage example.

## Test vectors

For parsing code, test vectors are generated using the existing
[go-coap][go-coap github] implementation written in [Go][go website].
Test vectors are generated using `./testvectors/generate.go` and
available as `./testvectors/*.bin` files. These files are tracked in the
Git repositories and thus Go is not necessarily needed to run existing
tests.

Each Zig test case embeds this file via [`@embedFile`][zig embedFile].
All existing Zig parser test cases can be run using:

	$ zig test src/packet.zig

New test cases can be added by modifying `./testvectors/generate.go` and
`./src/packet.zig`. Afterwards, the test case file needs to be generated
using:

	$ cd ./testvectors && go build -trimpath && ./testvectors

New test vectors need to be committed to the Git repository.

## License

This program is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the
Free Software Foundation, either version 3 of the License, or (at your
option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
Public License for more details.

You should have received a copy of the GNU General Public License along
with this program. If not, see <https://www.gnu.org/licenses/>.

[coap rfc]: https://datatracker.ietf.org/doc/rfc7252/
[zig web]: https://ziglang.org/
[zig-riscv github]: https://github.com/nmeum/zig-riscv-embedded
[go-coap github]: https://github.com/plgd-dev/go-coap
[go website]: https://golang.org
[zig embedFile]: https://ziglang.org/documentation/0.8.1/#embedFile
