package loader

import (
	"bytes"
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"time"
)

const (
	defaultRulesPath = "/etc/nft-rules/rules.nft"
	defaultNftPath   = "/nft"
	defaultInterval  = 5 * time.Second
)

type Runner func(context.Context, bool, []byte) error

type Loader struct {
	RulesPath string
	Interval  time.Duration
	RunNft    Runner
	Logger    *log.Logger
	lastHash  [sha256.Size]byte
	applied   bool
}

func New(logger *log.Logger) *Loader {
	rulesPath := os.Getenv("NFT_RULES_PATH")
	if rulesPath == "" {
		rulesPath = defaultRulesPath
	}
	nftPath := os.Getenv("NFT_BINARY_PATH")
	if nftPath == "" {
		nftPath = defaultNftPath
	}
	return &Loader{
		RulesPath: rulesPath,
		Interval:  defaultInterval,
		RunNft:    commandRunner(nftPath),
		Logger:    logger,
	}
}

func (l *Loader) Run(ctx context.Context) error {
	if err := l.Reconcile(ctx); err != nil {
		return fmt.Errorf("initial ruleset load: %w", err)
	}
	ticker := time.NewTicker(l.Interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			if err := l.Reconcile(ctx); err != nil && ctx.Err() == nil {
				l.Logger.Printf("ruleset update failed; previous rules remain active: %v", err)
			}
		}
	}
}

func (l *Loader) Reconcile(ctx context.Context) error {
	rules, err := os.ReadFile(l.RulesPath)
	if err != nil {
		return fmt.Errorf("read %s: %w", l.RulesPath, err)
	}
	if len(bytes.TrimSpace(rules)) == 0 {
		return errors.New("rules file is empty")
	}
	hash := sha256.Sum256(rules)
	if l.applied && hash == l.lastHash {
		return nil
	}
	if err := l.RunNft(ctx, true, rules); err != nil {
		return fmt.Errorf("validate ruleset: %w", err)
	}
	if err := l.RunNft(ctx, false, rules); err != nil {
		return fmt.Errorf("apply ruleset: %w", err)
	}
	l.lastHash = hash
	l.applied = true
	l.Logger.Printf("applied ruleset sha256=%x", hash[:8])
	return nil
}

func commandRunner(path string) Runner {
	return func(parent context.Context, check bool, rules []byte) error {
		ctx, cancel := context.WithTimeout(parent, 15*time.Second)
		defer cancel()
		args := []string{"-f", "-"}
		if check {
			args = append([]string{"-c"}, args...)
		}
		cmd := exec.CommandContext(ctx, path, args...)
		cmd.Stdin = bytes.NewReader(rules)
		output, err := cmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("nft %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(string(output)))
		}
		return nil
	}
}
