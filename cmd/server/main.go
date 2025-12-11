package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/kanywst/go-graceful-restart-poc/internal/app"

	"github.com/libp2p/go-reuseport"
)

const Port = "8080"

func main() {
	// 1. Use the reuseport library's listener
	listener, err := reuseport.Listen("tcp", ":"+Port)
	if err != nil {
		log.Fatalf("failed to create reusable port listener: %v", err)
	}

	log.Printf("Server starting on port %s with PID: %d\n", Port, os.Getpid())

	// 2. Create the HTTP server
	server := &http.Server{
		Handler: http.HandlerFunc(app.HealthCheckHandler),
	}

	// 3. Set up signal monitoring for termination signals (SIGTERM, SIGINT)
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)

	// 4. Start the server
	go func() {
		if err := server.Serve(listener); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server failed: %s\n", err)
		}
	}()

	// 5. Wait for termination signal
	<-stop
	log.Println("Received shutdown signal. Starting graceful shutdown...")

	// 6. Execute graceful shutdown
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown after timeout: %v", err)
	}

	log.Println("Server successfully shut down.")
}
