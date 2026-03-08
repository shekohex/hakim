package provider

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestGitHubClientDispatchWorkflow(t *testing.T) {
	t.Parallel()

	var captured dispatchRequest
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("expected POST, got %s", r.Method)
		}
		if !strings.Contains(r.RequestURI, "/actions/workflows/.github%2Fworkflows%2Fhakim-workspace.yml/dispatches") {
			t.Fatalf("unexpected request uri: %s", r.RequestURI)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-token" {
			t.Fatalf("unexpected authorization header: %s", got)
		}
		if err := json.NewDecoder(r.Body).Decode(&captured); err != nil {
			t.Fatalf("decode request body: %v", err)
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()

	client := &githubClient{
		baseURL: server.URL,
		token:   "test-token",
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
		},
	}

	err := client.dispatchWorkflow(context.Background(), "shekohex", "hakim", ".github/workflows/hakim-workspace.yml", dispatchRequest{
		Ref: "main",
		Inputs: map[string]string{
			"workspace_id": "workspace-1",
			"request_id":   "request-1",
		},
	})
	if err != nil {
		t.Fatalf("dispatchWorkflow returned error: %v", err)
	}

	if captured.Ref != "main" {
		t.Fatalf("unexpected ref: %s", captured.Ref)
	}
	if captured.Inputs["workspace_id"] != "workspace-1" {
		t.Fatalf("unexpected workspace_id input: %s", captured.Inputs["workspace_id"])
	}
	if captured.Inputs["request_id"] != "request-1" {
		t.Fatalf("unexpected request_id input: %s", captured.Inputs["request_id"])
	}
}

func TestGitHubClientCancelWorkflowRunAcceptsConflict(t *testing.T) {
	t.Parallel()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("expected POST, got %s", r.Method)
		}
		w.WriteHeader(http.StatusConflict)
		_, _ = w.Write([]byte(`{"message":"run already completed"}`))
	}))
	defer server.Close()

	client := &githubClient{
		baseURL: server.URL,
		token:   "test-token",
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
		},
	}

	if err := client.cancelWorkflowRun(context.Background(), "shekohex", "hakim", 42); err != nil {
		t.Fatalf("cancelWorkflowRun returned error: %v", err)
	}
}
