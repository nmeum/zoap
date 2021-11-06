package main

import (
	"os"
	"log"
	"path/filepath"

	"github.com/plgd-dev/go-coap/v2/message/codes"
	"github.com/plgd-dev/go-coap/v2/udp/message"
	coap "github.com/plgd-dev/go-coap/v2/message"
)

type genFn func() ([]byte, error)

func withPayload() ([]byte, error) {
	return message.Message{
		Code:      codes.DELETE,
		Token:     []byte{},
		Payload:   []byte("Hello"),
		MessageID: 1,
		Type:      message.Reset,
	}.Marshal()
}

func basicHeader() ([]byte, error) {
	return message.Message{
		Code:      codes.GET,
		Token:     []byte{},
		Payload:   []byte{},
		MessageID: 2342,
		Type:      message.Confirmable,
	}.Marshal()
}

func withToken() ([]byte, error) {
	return message.Message{
		Code:      codes.PUT,
		Token:     []byte{23, 42},
		Payload:   []byte{},
		MessageID: 5,
		Type:      message.Acknowledgement,
	}.Marshal()
}

func withOptions() ([]byte, error) {
	var opts coap.Options = []coap.Option{
		coap.Option{2, []byte{0xff}},
		coap.Option{23, []byte{13, 37}},
		coap.Option{65535, []byte{}},
	}

	return message.Message{
		Code:      codes.GET,
		Token:     []byte{},
		Payload:   []byte{},
		MessageID: 2342,
		Type:      message.Confirmable,
		Options:   opts,
	}.Marshal()
}

func main() {
	log.SetFlags(log.Lshortfile)

	testCases := []struct{
		Name string
		Func genFn
	}{
		{ "with-payload", withPayload },
		{ "basic-header", basicHeader },
		{ "with-token", withToken },
		{ "with-options", withOptions },
	}

	// Directory where source file is located.
	dir := filepath.Dir(os.Args[0])

	for _, testCase := range testCases {
		fp := filepath.Join(dir, testCase.Name+".bin")
		file, err := os.Create(fp)
		if err != nil {
			log.Fatal(err)
		}

		data, err := testCase.Func()
		if err != nil {
			file.Close()
			log.Fatal(err)
		}

		_, err = file.Write(data)
		if err != nil {
			file.Close()
			log.Fatal(err)
		}
		file.Close()
	}
}
