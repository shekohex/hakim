# Hakim Workspace Action

```yaml
name: Hakim Workspace

on:
  workflow_dispatch:
    inputs:
      workspace_id:
        required: true
        type: string
      workspace_name:
        required: true
        type: string
      manifest:
        required: true
        type: string

jobs:
  workspace:
    runs-on: ubuntu-latest
    timeout-minutes: 360
    permissions:
      actions: write
      contents: read
      packages: read
    steps:
      - uses: shekohex/hakim/.github/actions/hakim-workspace@main
        with:
          workspace_id: ${{ inputs.workspace_id }}
          workspace_name: ${{ inputs.workspace_name }}
          manifest: ${{ inputs.manifest }}
          age_secret_key: ${{ secrets.HAKIM_WORKSPACE_AGE_SECRET_KEY }}
          control_gh_token: ${{ github.token }}
```
