# zoap

A WiP [CoAP][rfc 7252] implementation for bare-metal [constrained devices][rfc 7228] in [Zig][zig web].

## Status

Presently, the majority of the CoAP standard is not implemented.
However, creating a very basic CoAP server which sends and receives
non-confirmable messages is possible and already done as part of my
[zig-riscv-embedded][zig-riscv github] project. Since the code focus
on constrained bare-metal targets, it is optimized for a small memory
footprint and uses statically allocated fixed-size buffers instead of
performing dynamic memory allocation. Furthermore, it does not use any
OS-specific code from the Zig standard library (e.g. Sockets).

The code is known to compile with Zig `0.9.1`.

## Usage

As noted above, this library targets freestanding constrained devices.
For this reason, all memory is statically allocated. To implement a CoAP
server with zoap, the central data structure is the Dispatcher. This
Dispatcher takes a list of Resources and forwards incoming requests to
them if the URI in the request matches one of the available resources.
Both, the dispatcher and the resources need to be statically allocated,
e.g. as global variables:

	const resources = &[_]zoap.Resource{
	    .{ .path = "hello", .handler = helloHandler },
	    .{ .path = "about", .handler = aboutHandler },
	};
	var dispatcher = zoap.Dispatcher{
	    .resources = resources,
	};

The code above allocates a dispatcher with two resources: `/hello` and
`/about`. An incoming CoAP request for either of those resources invokes
the associated handler function. The `helloHandler` implementation may
looks as follows:

	pub fn helloHandler(resp: *zoap.Response, req: *zoap.Request) codes.Code {
	    if (!req.header.code.equal(codes.GET))
	        return codes.BAD_METHOD;
	
	    const w = resp.payloadWriter();
	    w.writeAll("Hello, World!") catch {
	        return codes.INTERNAL_ERR;
	    };
	
	    return codes.CONTENT;
	}

The function takes two parameters: The resulting CoAP response and the
incoming CoAP request. The handler returns the CoAP response code for
the incoming request. The implementation above first checks the request
method, if it doesn't match the expected method a response with a
Method Not Allowed status code is returned. Otherwise, the
`helloHandler` writes `Hello, World!` to the response body and, unless an
error occurs, it responses with a successful content response code.

In order to invoke these handlers, incoming CoAP requests need to be
forwarded to the Dispatcher via the `Dispatcher.dispatch` method which
takes an incoming CoAP request as a parameter and forwards it to the
matching resource (if any). The method returns the appropriate CoAP
response. Since this library attempts to be OS-independent, the code for
retrieving incoming requests and sending responses to these requests
depends on your environment. For example, CoAP request may be read from
a UDP socket in a POSIX environment.

For or a more detailed and complete usage example refer to
[zig-riscv-embedded][zig-riscv github] which reads incoming requests
from a [SLIP][rfc 1055] serial interface.

## Test vectors

For parsing code, test vectors are created using the existing
[go-coap][go-coap github] implementation written in [Go][go website].
Test vectors are generated using `./src/testvectors/generate.go` and
available as `./src/testvectors/*.bin` files. These files are tracked
in the Git repositories and thus Go is not necessarily needed to run
existing tests.

Each Zig test case embeds this file via [`@embedFile`][zig embedFile].
All existing Zig parser test cases can be run using:

	$ zig test src/packet.zig

New test cases can be added by modifying `./src/testvectors/generate.go` and
`./src/packet.zig`. Afterwards, the test case files need to be regenerated
using:

	$ cd ./src/testvectors && go build -trimpath && ./testvectors

New test vectors must be committed to the Git repository.

## License

This program is free software: you can redistribute it and/or modify it
under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero
General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.

[rfc 7252]: https://datatracker.ietf.org/doc/rfc7252/
[rfc 7228]: https://datatracker.ietf.org/doc/rfc7228/
[rfc 1055]: https://datatracker.ietf.org/doc/rfc1055/
[zig web]: https://ziglang.org/
[zig-riscv github]: https://github.com/nmeum/zig-riscv-embedded
[go-coap github]: https://github.com/plgd-dev/go-coap
[go website]: https://golang.org
[zig embedFile]: https://ziglang.org/documentation/0.9.1/#embedFile
[zig import]: https://ziglang.org/documentation/0.9.1/#import
[git submodules]: https://git-scm.com/book/en/v2/Git-Tools-Submodules
[gyro github]: https://github.com/mattnite/gyro
