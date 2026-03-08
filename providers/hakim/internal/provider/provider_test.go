package provider

import "testing"

func TestResolveGitHubAPITokenPrefersConfig(t *testing.T) {
	t.Setenv("GITHUB_API_TOKEN", "env-token")

	if got := resolveGitHubAPIToken(" config-token "); got != "config-token" {
		t.Fatalf("unexpected token: %q", got)
	}
}

func TestResolveGitHubAPITokenFallsBackToEnv(t *testing.T) {
	t.Setenv("GITHUB_API_TOKEN", " env-token ")

	if got := resolveGitHubAPIToken("   "); got != "env-token" {
		t.Fatalf("unexpected token: %q", got)
	}
}

func TestResolveGitHubAPITokenAllowsMissingValue(t *testing.T) {
	t.Setenv("GITHUB_API_TOKEN", "")

	if got := resolveGitHubAPIToken(""); got != "" {
		t.Fatalf("unexpected token: %q", got)
	}
}
