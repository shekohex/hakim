package provider

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"filippo.io/age"
	"filippo.io/age/armor"
)

func TestGitHubActionsRunResourceWaitForDispatchedRun(t *testing.T) {
	t.Parallel()

	createdAt := time.Now().UTC()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		response := workflowRunsResponse{
			WorkflowRuns: []workflowRun{
				{
					ID:           10,
					DisplayTitle: "Hakim Workspace workspace-1 wrong-request",
					Status:       "in_progress",
					CreatedAt:    createdAt,
				},
				{
					ID:           11,
					DisplayTitle: "Hakim Workspace workspace-1 request-1",
					HTMLURL:      "https://github.com/shekohex/hakim/actions/runs/11",
					Status:       "queued",
					CreatedAt:    createdAt,
				},
			},
		}

		if err := json.NewEncoder(w).Encode(response); err != nil {
			t.Fatalf("encode response: %v", err)
		}
	}))
	defer server.Close()

	resource := &gitHubActionsRunResource{
		client: &githubClient{
			baseURL: server.URL,
			token:   "test-token",
			httpClient: &http.Client{
				Timeout: 5 * time.Second,
			},
		},
	}

	run, err := resource.waitForDispatchedRun(context.Background(), "shekohex", "hakim", ".github/workflows/hakim-workspace.yml", "workspace-1", "request-1", createdAt.Add(-1*time.Second), 2*time.Second)
	if err != nil {
		t.Fatalf("waitForDispatchedRun returned error: %v", err)
	}

	if run.ID != 11 {
		t.Fatalf("unexpected run id: %d", run.ID)
	}
	if run.DisplayTitle != "Hakim Workspace workspace-1 request-1" {
		t.Fatalf("unexpected display title: %s", run.DisplayTitle)
	}
}

func TestEncryptManifestRoundTrip(t *testing.T) {
	t.Parallel()

	identity, err := age.GenerateX25519Identity()
	if err != nil {
		t.Fatalf("GenerateX25519Identity returned error: %v", err)
	}

	plaintext := `{"workspace_id":"workspace-1"}`
	ciphertext, err := encryptManifest(identity.Recipient().String(), plaintext)
	if err != nil {
		t.Fatalf("encryptManifest returned error: %v", err)
	}

	reader, err := age.Decrypt(armor.NewReader(strings.NewReader(ciphertext)), identity)
	if err != nil {
		t.Fatalf("Decrypt returned error: %v", err)
	}

	decrypted, err := io.ReadAll(reader)
	if err != nil {
		t.Fatalf("ReadAll returned error: %v", err)
	}

	if string(decrypted) != plaintext {
		t.Fatalf("unexpected plaintext: %s", string(decrypted))
	}
}
