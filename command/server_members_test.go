package command

import (
	"strings"
	"testing"

	"github.com/mitchellh/cli"
)

func TestServerMembersCommand_Implements(t *testing.T) {
	var _ cli.Command = &ServerMembersCommand{}
}

func TestServerMembersCommand_Run(t *testing.T) {
	srv, client, url := testServer(t, nil)
	defer srv.Stop()

	ui := new(cli.MockUi)
	cmd := &ServerMembersCommand{Meta: Meta{Ui: ui}}

	// Get our own node name
	name, err := client.Agent().NodeName()
	if err != nil {
		t.Fatalf("err: %s", err)
	}

	// Query the members
	if code := cmd.Run([]string{"-address=" + url}); code != 0 {
		t.Fatalf("expected exit 0, got: %d", code)
	}
	if out := ui.OutputWriter.String(); !strings.Contains(out, name) {
		t.Fatalf("expected %q in output, got: %s", name, out)
	}
	ui.OutputWriter.Reset()

	// Query members with detailed output
	if code := cmd.Run([]string{"-address=" + url, "-detailed"}); code != 0 {
		t.Fatalf("expected exit 0, got: %d", code)
	}
	if out := ui.OutputWriter.String(); !strings.Contains(out, "Tags") {
		t.Fatalf("expected tags in output, got: %s", out)
	}
}
