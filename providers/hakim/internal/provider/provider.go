package provider

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/hashicorp/terraform-plugin-framework/datasource"
	"github.com/hashicorp/terraform-plugin-framework/provider"
	providerschema "github.com/hashicorp/terraform-plugin-framework/provider/schema"
	"github.com/hashicorp/terraform-plugin-framework/resource"
	"github.com/hashicorp/terraform-plugin-framework/types"
)

var _ provider.Provider = (*hakimProvider)(nil)

type hakimProvider struct {
	version string
}

type hakimProviderModel struct {
	Token types.String `tfsdk:"token"`
}

type githubClient struct {
	baseURL    string
	token      string
	httpClient *http.Client
}

func New(version string) func() provider.Provider {
	return func() provider.Provider {
		return &hakimProvider{version: version}
	}
}

func (p *hakimProvider) Metadata(_ context.Context, _ provider.MetadataRequest, resp *provider.MetadataResponse) {
	resp.TypeName = "hakim"
	resp.Version = p.version
}

func (p *hakimProvider) Schema(_ context.Context, _ provider.SchemaRequest, resp *provider.SchemaResponse) {
	resp.Schema = providerschema.Schema{
		Attributes: map[string]providerschema.Attribute{
			"token": providerschema.StringAttribute{
				Optional:  true,
				Sensitive: true,
			},
		},
	}
}

func (p *hakimProvider) Configure(ctx context.Context, req provider.ConfigureRequest, resp *provider.ConfigureResponse) {
	var config hakimProviderModel

	resp.Diagnostics.Append(req.Config.Get(ctx, &config)...)
	if resp.Diagnostics.HasError() {
		return
	}

	token := strings.TrimSpace(config.Token.ValueString())
	if token == "" {
		token = strings.TrimSpace(os.Getenv("GITHUB_API_TOKEN"))
	}

	if token == "" {
		resp.Diagnostics.AddError("Missing GitHub API token", "Set provider token or GITHUB_API_TOKEN.")
		return
	}

	client := &githubClient{
		baseURL: "https://api.github.com",
		token:   token,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}

	resp.ResourceData = client
	resp.DataSourceData = client
}

func (p *hakimProvider) Resources(_ context.Context) []func() resource.Resource {
	return []func() resource.Resource{
		NewGitHubActionsRunResource,
	}
}

func (p *hakimProvider) DataSources(_ context.Context) []func() datasource.DataSource {
	return nil
}

func parseRepository(repository string) (string, string, error) {
	owner, repo, ok := strings.Cut(repository, "/")
	if !ok || strings.TrimSpace(owner) == "" || strings.TrimSpace(repo) == "" {
		return "", "", fmt.Errorf("repository must be in owner/repo format")
	}

	return owner, repo, nil
}
