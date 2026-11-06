package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/samr037/talos-nftables/internal/loader"
)

func main() {
	logger := log.New(os.Stdout, "nft-rules: ", log.LstdFlags|log.LUTC)
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	l := loader.New(logger)
	if err := l.Run(ctx); err != nil {
		logger.Fatal(err)
	}
}
