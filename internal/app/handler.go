package app

import (
	"fmt"
	"net/http"
	"os"
)

// HealthCheckHandler returns the server's health status and process ID.
// This allows you to see which process is handling the request.
func HealthCheckHandler(w http.ResponseWriter, r *http.Request) {
	// Get the current process ID
	pid := os.Getpid()

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)

	// Include the PID in the response body
	fmt.Fprintf(w, "OK. Handled by PID: %d\n", pid)
}
