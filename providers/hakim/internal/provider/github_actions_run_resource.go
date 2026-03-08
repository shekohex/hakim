package provider

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"strconv"
	"strings"
	"time"

	"filippo.io/age"
	"filippo.io/age/armor"
	"github.com/google/uuid"
	"github.com/hashicorp/terraform-plugin-framework/path"
	"github.com/hashicorp/terraform-plugin-framework/resource"
	"github.com/hashicorp/terraform-plugin-framework/resource/schema"
	"github.com/hashicorp/terraform-plugin-framework/resource/schema/int64default"
	"github.com/hashicorp/terraform-plugin-framework/resource/schema/planmodifier"
	"github.com/hashicorp/terraform-plugin-framework/resource/schema/stringplanmodifier"
	"github.com/hashicorp/terraform-plugin-framework/types"
)

var _ resource.Resource = (*gitHubActionsRunResource)(nil)

type gitHubActionsRunResource struct {
	client *githubClient
}

type gitHubActionsRunResourceModel struct {
	ID               types.String `tfsdk:"id"`
	Repository       types.String `tfsdk:"repository"`
	WorkflowFile     types.String `tfsdk:"workflow_file"`
	WorkflowRef      types.String `tfsdk:"workflow_ref"`
	WorkspaceID      types.String `tfsdk:"workspace_id"`
	WorkspaceName    types.String `tfsdk:"workspace_name"`
	ManifestJSON     types.String `tfsdk:"manifest_json"`
	AgePublicKey     types.String `tfsdk:"age_public_key"`
	RunLookupTimeout types.Int64  `tfsdk:"run_lookup_timeout_seconds"`
	CancelTimeout    types.Int64  `tfsdk:"cancel_timeout_seconds"`
	RequestID        types.String `tfsdk:"request_id"`
	RunID            types.String `tfsdk:"run_id"`
	HTMLURL          types.String `tfsdk:"html_url"`
	Status           types.String `tfsdk:"status"`
	Conclusion       types.String `tfsdk:"conclusion"`
}

func NewGitHubActionsRunResource() resource.Resource {
	return &gitHubActionsRunResource{}
}

func (r *gitHubActionsRunResource) Metadata(_ context.Context, req resource.MetadataRequest, resp *resource.MetadataResponse) {
	resp.TypeName = req.ProviderTypeName + "_github_actions_run"
}

func (r *gitHubActionsRunResource) Schema(_ context.Context, _ resource.SchemaRequest, resp *resource.SchemaResponse) {
	requiresReplace := []planmodifier.String{stringplanmodifier.RequiresReplace()}
	computedString := []planmodifier.String{stringplanmodifier.UseStateForUnknown()}

	resp.Schema = schema.Schema{
		Attributes: map[string]schema.Attribute{
			"id":                         schema.StringAttribute{Computed: true, PlanModifiers: computedString},
			"repository":                 schema.StringAttribute{Required: true, PlanModifiers: requiresReplace},
			"workflow_file":              schema.StringAttribute{Required: true, PlanModifiers: requiresReplace},
			"workflow_ref":               schema.StringAttribute{Required: true, PlanModifiers: requiresReplace},
			"workspace_id":               schema.StringAttribute{Required: true, PlanModifiers: requiresReplace},
			"workspace_name":             schema.StringAttribute{Required: true, PlanModifiers: requiresReplace},
			"manifest_json":              schema.StringAttribute{Required: true, Sensitive: true, PlanModifiers: requiresReplace},
			"age_public_key":             schema.StringAttribute{Required: true, PlanModifiers: requiresReplace},
			"run_lookup_timeout_seconds": schema.Int64Attribute{Optional: true, Computed: true, Default: int64default.StaticInt64(120)},
			"cancel_timeout_seconds":     schema.Int64Attribute{Optional: true, Computed: true, Default: int64default.StaticInt64(300)},
			"request_id":                 schema.StringAttribute{Computed: true, PlanModifiers: computedString},
			"run_id":                     schema.StringAttribute{Computed: true, PlanModifiers: computedString},
			"html_url":                   schema.StringAttribute{Computed: true, PlanModifiers: computedString},
			"status":                     schema.StringAttribute{Computed: true, PlanModifiers: computedString},
			"conclusion":                 schema.StringAttribute{Computed: true, PlanModifiers: computedString},
		},
	}
}

func (r *gitHubActionsRunResource) Configure(_ context.Context, req resource.ConfigureRequest, resp *resource.ConfigureResponse) {
	if req.ProviderData == nil {
		return
	}

	client, ok := req.ProviderData.(*githubClient)
	if !ok {
		resp.Diagnostics.AddError("Unexpected provider data type", fmt.Sprintf("Expected *githubClient, got %T", req.ProviderData))
		return
	}

	r.client = client
}

func (r *gitHubActionsRunResource) Create(ctx context.Context, req resource.CreateRequest, resp *resource.CreateResponse) {
	var plan gitHubActionsRunResourceModel

	resp.Diagnostics.Append(req.Plan.Get(ctx, &plan)...)
	if resp.Diagnostics.HasError() {
		return
	}

	if r.client == nil {
		resp.Diagnostics.AddError("Provider not configured", "The Hakim provider client is unavailable.")
		return
	}

	owner, repo, err := parseRepository(plan.Repository.ValueString())
	if err != nil {
		resp.Diagnostics.AddAttributeError(path.Root("repository"), "Invalid repository", err.Error())
		return
	}

	requestID := uuid.NewString()
	manifest, err := encryptManifest(plan.AgePublicKey.ValueString(), plan.ManifestJSON.ValueString())
	if err != nil {
		resp.Diagnostics.AddAttributeError(path.Root("age_public_key"), "Unable to encrypt manifest", err.Error())
		return
	}

	dispatchAt := time.Now().UTC().Add(-5 * time.Second)
	err = r.client.dispatchWorkflow(ctx, owner, repo, plan.WorkflowFile.ValueString(), dispatchRequest{
		Ref: plan.WorkflowRef.ValueString(),
		Inputs: map[string]string{
			"workspace_id":   plan.WorkspaceID.ValueString(),
			"workspace_name": plan.WorkspaceName.ValueString(),
			"request_id":     requestID,
			"manifest":       manifest,
		},
	})
	if err != nil {
		resp.Diagnostics.AddError("Unable to dispatch workflow", err.Error())
		return
	}

	run, err := r.waitForDispatchedRun(ctx, owner, repo, plan.WorkflowFile.ValueString(), plan.WorkspaceID.ValueString(), requestID, dispatchAt, time.Duration(plan.RunLookupTimeout.ValueInt64())*time.Second)
	if err != nil {
		resp.Diagnostics.AddError("Unable to discover workflow run", err.Error())
		return
	}

	plan.ID = types.StringValue(strconv.FormatInt(run.ID, 10))
	plan.RequestID = types.StringValue(requestID)
	plan.RunID = types.StringValue(strconv.FormatInt(run.ID, 10))
	plan.HTMLURL = types.StringValue(run.HTMLURL)
	plan.Status = types.StringValue(run.Status)
	if run.Conclusion != nil {
		plan.Conclusion = types.StringValue(*run.Conclusion)
	} else {
		plan.Conclusion = types.StringNull()
	}

	resp.Diagnostics.Append(resp.State.Set(ctx, &plan)...)
}

func (r *gitHubActionsRunResource) Read(ctx context.Context, req resource.ReadRequest, resp *resource.ReadResponse) {
	var state gitHubActionsRunResourceModel

	resp.Diagnostics.Append(req.State.Get(ctx, &state)...)
	if resp.Diagnostics.HasError() {
		return
	}

	owner, repo, err := parseRepository(state.Repository.ValueString())
	if err != nil {
		resp.Diagnostics.AddAttributeError(path.Root("repository"), "Invalid repository", err.Error())
		return
	}

	runID, err := strconv.ParseInt(state.RunID.ValueString(), 10, 64)
	if err != nil {
		resp.Diagnostics.AddAttributeError(path.Root("run_id"), "Invalid run id", err.Error())
		return
	}

	run, err := r.client.getWorkflowRun(ctx, owner, repo, runID)
	if err != nil {
		var githubErr *githubError
		if errorAs(err, &githubErr) && githubErr.statusCode == 404 {
			resp.State.RemoveResource(ctx)
			return
		}
		resp.Diagnostics.AddError("Unable to read workflow run", err.Error())
		return
	}

	state.ID = types.StringValue(strconv.FormatInt(run.ID, 10))
	state.RunID = types.StringValue(strconv.FormatInt(run.ID, 10))
	state.HTMLURL = types.StringValue(run.HTMLURL)
	state.Status = types.StringValue(run.Status)
	if run.Conclusion != nil {
		state.Conclusion = types.StringValue(*run.Conclusion)
	} else {
		state.Conclusion = types.StringNull()
	}

	resp.Diagnostics.Append(resp.State.Set(ctx, &state)...)
}

func (r *gitHubActionsRunResource) Update(ctx context.Context, req resource.UpdateRequest, resp *resource.UpdateResponse) {
	var plan gitHubActionsRunResourceModel

	resp.Diagnostics.Append(req.Plan.Get(ctx, &plan)...)
	if resp.Diagnostics.HasError() {
		return
	}

	resp.Diagnostics.Append(resp.State.Set(ctx, &plan)...)
}

func (r *gitHubActionsRunResource) Delete(ctx context.Context, req resource.DeleteRequest, resp *resource.DeleteResponse) {
	var state gitHubActionsRunResourceModel

	resp.Diagnostics.Append(req.State.Get(ctx, &state)...)
	if resp.Diagnostics.HasError() {
		return
	}

	owner, repo, err := parseRepository(state.Repository.ValueString())
	if err != nil {
		resp.Diagnostics.AddAttributeError(path.Root("repository"), "Invalid repository", err.Error())
		return
	}

	runID, err := strconv.ParseInt(state.RunID.ValueString(), 10, 64)
	if err != nil {
		resp.Diagnostics.AddAttributeError(path.Root("run_id"), "Invalid run id", err.Error())
		return
	}

	if err := r.client.cancelWorkflowRun(ctx, owner, repo, runID); err != nil {
		resp.Diagnostics.AddError("Unable to cancel workflow run", err.Error())
		return
	}

	deadline := time.Now().Add(time.Duration(state.CancelTimeout.ValueInt64()) * time.Second)
	for time.Now().Before(deadline) {
		run, err := r.client.getWorkflowRun(ctx, owner, repo, runID)
		if err != nil {
			var githubErr *githubError
			if errorAs(err, &githubErr) && githubErr.statusCode == 404 {
				return
			}
			resp.Diagnostics.AddError("Unable to confirm workflow cancellation", err.Error())
			return
		}

		if run.Status == "completed" {
			return
		}

		time.Sleep(5 * time.Second)
	}

	resp.Diagnostics.AddWarning("Workflow run is still stopping", fmt.Sprintf("Run %s did not reach completed status before timeout.", state.RunID.ValueString()))
}

func (r *gitHubActionsRunResource) ImportState(context.Context, resource.ImportStateRequest, *resource.ImportStateResponse) {
}

func (r *gitHubActionsRunResource) waitForDispatchedRun(ctx context.Context, owner, repo, workflowFile, workspaceID, requestID string, dispatchAt time.Time, timeout time.Duration) (*workflowRun, error) {
	deadline := time.Now().Add(timeout)
	expectedTitle := fmt.Sprintf("Hakim Workspace %s %s", workspaceID, requestID)

	for time.Now().Before(deadline) {
		runs, err := r.client.listWorkflowRuns(ctx, owner, repo, workflowFile)
		if err != nil {
			return nil, err
		}

		for _, run := range runs {
			if run.DisplayTitle != expectedTitle {
				continue
			}
			if run.CreatedAt.Before(dispatchAt) {
				continue
			}
			return &run, nil
		}

		time.Sleep(3 * time.Second)
	}

	return nil, fmt.Errorf("timed out waiting for workflow run %q", expectedTitle)
}

func encryptManifest(publicKey, plaintext string) (string, error) {
	recipient, err := age.ParseX25519Recipient(strings.TrimSpace(publicKey))
	if err != nil {
		return "", fmt.Errorf("parse age recipient: %w", err)
	}

	var buffer bytes.Buffer
	armorWriter := armor.NewWriter(&buffer)
	encryptWriter, err := age.Encrypt(armorWriter, recipient)
	if err != nil {
		return "", fmt.Errorf("start age encryption: %w", err)
	}

	if _, err := io.WriteString(encryptWriter, plaintext); err != nil {
		return "", fmt.Errorf("write encrypted payload: %w", err)
	}

	if err := encryptWriter.Close(); err != nil {
		return "", fmt.Errorf("close encrypted payload: %w", err)
	}

	if err := armorWriter.Close(); err != nil {
		return "", fmt.Errorf("close armor payload: %w", err)
	}

	return buffer.String(), nil
}
