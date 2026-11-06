package loader

import (
	"context"
	"errors"
	"io"
	"log"
	"os"
	"path/filepath"
	"testing"
)

func TestReconcileChecksBeforeApplyAndKeepsLastGoodRules(t *testing.T) {
	path := filepath.Join(t.TempDir(), "rules.nft")
	write := func(s string) {
		t.Helper()
		if err := os.WriteFile(path, []byte(s), 0600); err != nil {
			t.Fatal(err)
		}
	}
	write("table inet test {}")
	var calls []bool
	l := &Loader{RulesPath: path, Logger: log.New(io.Discard, "", 0)}
	l.RunNft = func(_ context.Context, check bool, rules []byte) error {
		calls = append(calls, check)
		if check && string(rules) == "invalid" {
			return errors.New("syntax error")
		}
		return nil
	}
	if err := l.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := l.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	write("invalid")
	if err := l.Reconcile(context.Background()); err == nil {
		t.Fatal("invalid ruleset should fail")
	}
	write("table inet test {}")
	if err := l.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(calls) != 3 || !calls[0] || calls[1] || !calls[2] {
		t.Fatalf("unexpected nft calls: %v", calls)
	}
}
