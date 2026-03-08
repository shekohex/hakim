package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path"
	"strconv"
	"strings"
	"time"
)

type githubError struct {
	statusCode int
	body       string
}

func (e *githubError) Error() string {
	return fmt.Sprintf("github api returned status %d: %s", e.statusCode, e.body)
}

type dispatchRequest struct {
	Ref    string            `json:"ref"`
	Inputs map[string]string `json:"inputs,omitempty"`
}

type workflowRun struct {
	ID           int64      `json:"id"`
	HTMLURL      string     `json:"html_url"`
	Status       string     `json:"status"`
	Conclusion   *string    `json:"conclusion"`
	DisplayTitle string     `json:"display_title"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    *time.Time `json:"updated_at"`
}

type workflowRunsResponse struct {
	WorkflowRuns []workflowRun `json:"workflow_runs"`
}

func (c *githubClient) dispatchWorkflow(ctx context.Context, owner, repo, workflowFile string, payload dispatchRequest) error {
	encodedWorkflowFile := url.PathEscape(workflowFile)
	apiPath := path.Join("repos", owner, repo, "actions", "workflows", encodedWorkflowFile, "dispatches")
	_, err := c.doJSON(ctx, http.MethodPost, apiPath, payload)
	return err
}

func (c *githubClient) listWorkflowRuns(ctx context.Context, owner, repo, workflowFile string) ([]workflowRun, error) {
	encodedWorkflowFile := url.PathEscape(workflowFile)
	apiPath := path.Join("repos", owner, repo, "actions", "workflows", encodedWorkflowFile, "runs") + "?event=workflow_dispatch&per_page=100"
	body, err := c.doJSON(ctx, http.MethodGet, apiPath, nil)
	if err != nil {
		return nil, err
	}

	var response workflowRunsResponse
	if err := json.Unmarshal(body, &response); err != nil {
		return nil, fmt.Errorf("unmarshal workflow runs response: %w", err)
	}

	return response.WorkflowRuns, nil
}

func (c *githubClient) getWorkflowRun(ctx context.Context, owner, repo string, runID int64) (*workflowRun, error) {
	apiPath := path.Join("repos", owner, repo, "actions", "runs", strconv.FormatInt(runID, 10))
	body, err := c.doJSON(ctx, http.MethodGet, apiPath, nil)
	if err != nil {
		return nil, err
	}

	var run workflowRun
	if err := json.Unmarshal(body, &run); err != nil {
		return nil, fmt.Errorf("unmarshal workflow run response: %w", err)
	}

	return &run, nil
}

func (c *githubClient) cancelWorkflowRun(ctx context.Context, owner, repo string, runID int64) error {
	apiPath := path.Join("repos", owner, repo, "actions", "runs", strconv.FormatInt(runID, 10), "cancel")
	_, err := c.doJSON(ctx, http.MethodPost, apiPath, nil)
	if err != nil {
		var githubErr *githubError
		if ok := errorAs(err, &githubErr); ok {
			if githubErr.statusCode == http.StatusNotFound || githubErr.statusCode == http.StatusConflict || githubErr.statusCode == http.StatusUnprocessableEntity {
				return nil
			}
		}
		return err
	}

	return nil
}

func (c *githubClient) doJSON(ctx context.Context, method, apiPath string, payload any) ([]byte, error) {
	var bodyReader io.Reader
	if payload != nil {
		bodyBytes, err := json.Marshal(payload)
		if err != nil {
			return nil, fmt.Errorf("marshal request payload: %w", err)
		}
		bodyReader = bytes.NewReader(bodyBytes)
	}

	requestURL := strings.TrimRight(c.baseURL, "/") + "/" + strings.TrimLeft(apiPath, "/")
	req, err := http.NewRequestWithContext(ctx, method, requestURL, bodyReader)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("perform request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response body: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, &githubError{statusCode: resp.StatusCode, body: string(body)}
	}

	return body, nil
}

func errorAs(err error, target any) bool {
	return errors.As(err, target)
}
