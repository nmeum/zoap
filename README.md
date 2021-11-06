# zoap

A WiP [CoAP][rfc 7252] implementation for bare-metal [constrained devices][rfc 7228].

## Status

Presently, the majority of the CoAP standard is not implemented.
However, creating a very basic CoAP server which sends and receives
non-confirmable messages is possible and already done as part of my
[zig-riscv-embedded][zig-riscv github] project. Since the code focus
on constrained bare-metal targets, it is optimized for a small memory
footprint and uses statically allocated fixed-size buffers instead of
performing dynamic memory allocation. Furthermore, it does not use any
OS-specific code from the Zig standard library (e.g. Sockets).

The code is known to compile with Zig `0.8.1`.

## Installation

Zig packages are simply Zig source trees and are imported using
[`@import`][zig import] just like code from the Zig standard library.
Therefore, the zoap source tree must be added to the Zig codebase using
it. This can, for example, be achieved using [git submodules][git submodules]
or a third-party package manager like [gyro][gyro github].

For the former method, the package source tree needs to be explicitly
added to `build.rs`. Assuming, the submodule was added as `./zoap` in
the directory root the following code should be sufficient:

```Zig
exe.addPackage(std.build.Pkg{
    .name = "zoap",
    .path = "./zoap/src/zoap.zig",
});
```

Afterwards, simply import zoap using `const zoap = @import("zoap");`.

## Usage

See [zig-riscv-embedded][zig-riscv github] for a usage example.

## Test vectors

For parsing code, test vectors are created using the existing
[go-coap][go-coap github] implementation written in [Go][go website].
Test vectors are generated using `./testvectors/generate.go` and
available as `./testvectors/*.bin` files. These files are tracked in the
Git repositories and thus Go is not necessarily needed to run existing
tests.

Each Zig test case embeds this file via [`@embedFile`][zig embedFile].
All existing Zig parser test cases can be run using:

	$ zig test src/packet.zig

New test cases can be added by modifying `./testvectors/generate.go` and
`./src/packet.zig`. Afterwards, the test case files need to be
regenerated using:

	$ cd ./testvectors && go build -trimpath && ./testvectors

New test vectors must be committed to the Git repository.

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

[rfc 7252]: https://datatracker.ietf.org/doc/rfc7252/
[rfc 7228]: https://datatracker.ietf.org/doc/rfc7228/
[zig web]: https://ziglang.org/
[zig-riscv github]: https://github.com/nmeum/zig-riscv-embedded
[go-coap github]: https://github.com/plgd-dev/go-coap
[go website]: https://golang.org
[zig embedFile]: https://ziglang.org/documentation/0.8.1/#embedFile
[zig import]: https://ziglang.org/documentation/0.8.1/#import
[git submodules]: https://git-scm.com/book/en/v2/Git-Tools-Submodules
[gyro github]: https://github.com/mattnite/gyro
