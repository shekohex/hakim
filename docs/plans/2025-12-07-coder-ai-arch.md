# Coder AI Tasks Architecture Guide

This document provides a comprehensive guide to understanding how Coder's AI Tasks feature works, from the Terraform template configuration to the frontend rendering.

## Table of Contents

- [Overview](#overview)
- [Architecture Diagram](#architecture-diagram)
- [Frontend Structure](#frontend-structure)
  - [Tasks List Page](#tasks-list-page)
  - [Task Detail Page](#task-detail-page)
  - [How the Chat App is Rendered](#how-the-chat-app-is-rendered)
- [Backend Structure](#backend-structure)
  - [Task Creation Flow](#task-creation-flow)
  - [Task-to-App Association](#task-to-app-association)
- [Template Configuration](#template-configuration)
  - [The `coder_ai_task` Resource](#the-coder_ai_task-resource)
  - [The `coder_app` Resource](#the-coder_app-resource)
  - [Linking Tasks to Apps](#linking-tasks-to-apps)
- [The AgentAPI Module](#the-agentapi-module)
  - [What is AgentAPI?](#what-is-agentapi)
  - [Module Structure](#module-structure)
  - [Key Components](#key-components)
- [Creating Custom AI Task Modules](#creating-custom-ai-task-modules)
  - [Minimum Requirements](#minimum-requirements)
  - [Example: Custom Chat Module](#example-custom-chat-module)
- [Real-World Example: OpenCode Module](#real-world-example-opencode-module)
- [Customization Options](#customization-options)
- [Troubleshooting](#troubleshooting)

---

## Overview

Coder AI Tasks is a feature that allows users to run AI-assisted coding tasks within Coder workspaces. The system consists of:

1. **A Task Record**: Stored in the database, tracking the task's prompt, status, and associated workspace.
2. **A Workspace**: The compute environment where the AI agent runs.
3. **A Sidebar App**: A web application (typically running AgentAPI) that provides the chat interface.
4. **The Task UI**: A frontend page that embeds the sidebar app in an iframe alongside other workspace apps.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Coder Frontend                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  /tasks                        │  /tasks/:username/:taskId                  │
│  ┌───────────────────────────┐ │  ┌─────────────────────────────────────┐   │
│  │     TasksPage.tsx         │ │  │         TaskPage.tsx                │   │
│  │  ┌─────────────────────┐  │ │  │  ┌───────────┬───────────────────┐  │   │
│  │  │   TaskPrompt        │  │ │  │  │ Sidebar   │   TaskApps        │  │   │
│  │  │   (Create new task) │  │ │  │  │ App       │   (Preview, etc)  │  │   │
│  │  └─────────────────────┘  │ │  │  │ (iframe)  │                   │  │   │
│  │  ┌─────────────────────┐  │ │  │  │           │                   │  │   │
│  │  │   TasksTable        │  │ │  │  │ AgentAPI  │                   │  │   │
│  │  │   (List of tasks)   │  │ │  │  │ Chat UI   │                   │  │   │
│  │  └─────────────────────┘  │ │  │  └───────────┴───────────────────┘  │   │
│  └───────────────────────────┘ │  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                          │
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Coder Backend                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│  coderd/aitasks.go                                                          │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  - POST /tasks/{user}           Create task + workspace              │   │
│  │  - GET  /tasks                  List tasks                           │   │
│  │  - GET  /tasks/{user}/{task}    Get task details                     │   │
│  │  - POST /tasks/{user}/{task}/send  Send message to AgentAPI          │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                          │
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Workspace (Agent)                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌────────────────┐    ┌────────────────┐    ┌────────────────────────┐     │
│  │  coder_agent   │───▶│  coder_app     │───▶│  AgentAPI Server       │     │
│  │                │    │  (agentapi_web)│    │  localhost:3284        │     │
│  └────────────────┘    └────────────────┘    │  ┌──────────────────┐  │     │
│         │                      │             │  │  AI Coding Agent │  │     │
│         ▼                      │             │  │  (Claude, etc)   │  │     │
│  ┌────────────────┐            │             │  └──────────────────┘  │     │
│  │ coder_ai_task  │────────────┘             └────────────────────────┘     │
│  │ sidebar_app.id │                                                         │
│  └────────────────┘                                                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Frontend Structure

### Tasks List Page

**Location**: `site/src/pages/TasksPage/TasksPage.tsx`
**Route**: `/tasks`

This page displays:
- A prompt input for creating new tasks (`TaskPrompt` component)
- A table of existing tasks (`TasksTable` component)
- Filtering options (All tasks vs. Waiting for input)
- Batch actions (bulk delete)

Key components:
- `TaskPrompt.tsx` - The form for creating new tasks, including template and preset selection
- `TasksTable.tsx` - The table displaying task list with status, owner, and actions
- `UsersCombobox.tsx` - Filter tasks by owner

### Task Detail Page

**Location**: `site/src/pages/TaskPage/TaskPage.tsx`
**Route**: `/tasks/:username/:taskId`

This page uses a **resizable panel layout** (`react-resizable-panels`):
- **Left Panel (25%)**: The sidebar app (chat interface) rendered in an iframe
- **Right Panel (75%)**: Other workspace apps (Preview, Terminal, etc.)

Key components:
- `TaskAppIframe.tsx` - Renders the sidebar app in an iframe
- `TaskApps.tsx` - Renders additional workspace apps
- `TaskTopbar.tsx` - Shows task title, status, and actions
- `TasksSidebar.tsx` - Navigation sidebar for switching between tasks

### How the Chat App is Rendered

The frontend discovers which app to display as the "chat" interface through the following mechanism:

```typescript
// In TaskPage.tsx
const chatApp = getAllAppsWithAgent(workspace).find(
    (app) => app.id === task.workspace_app_id,
);

// If found, render it in the sidebar
<TaskAppIFrame active workspace={workspace} app={chatApp} />
```

**The `workspace_app_id` on the Task object is set by the backend** based on the `coder_ai_task.sidebar_app.id` attribute in the template.

---

## Backend Structure

### Task Creation Flow

**Location**: `coderd/aitasks.go`

1. User submits a prompt via `POST /tasks/{user}`
2. Backend validates the template version has a `coder_ai_task` resource
3. A new Task record is created in the database
4. A new Workspace is created using the specified template
5. The Task is linked to the Workspace
6. The workspace builds and starts the agent
7. The AgentAPI service starts and becomes available

### Task-to-App Association

The association between a Task and its sidebar app happens during **template provisioning**:

```go
// In provisioner/terraform/resources.go (lines 1017-1037)
for _, resource := range tfResourcesAITasks {
    var task provider.AITask
    mapstructure.Decode(resource.AttributeValues, &task)

    appID := task.AppID
    if appID == "" && len(task.SidebarApp) > 0 {
        appID = task.SidebarApp[0].ID
    }

    aiTasks = append(aiTasks, &proto.AITask{
        Id:    task.ID,
        AppId: appID,
        SidebarApp: &proto.AITaskSidebarApp{
            Id: appID,
        },
    })
}
```

This extracts the `sidebar_app.id` (or legacy `app_id`) from the `coder_ai_task` resource and stores it for later use.

---

## Template Configuration

### The `coder_ai_task` Resource

The `coder_ai_task` Terraform resource marks a template as AI Task-enabled:

```hcl
resource "coder_ai_task" "main" {
  sidebar_app {
    id = coder_app.agentapi_web.id
  }
}
```

**Key attributes:**
- `sidebar_app.id` (required): The ID of the `coder_app` to use as the chat interface

### The `coder_app` Resource

A standard Coder app resource that serves as the sidebar:

```hcl
resource "coder_app" "agentapi_web" {
  slug         = "chat"
  display_name = "AI Chat"
  agent_id     = coder_agent.main.id
  url          = "http://localhost:3284/"
  icon         = "/icon/chat.svg"
  subdomain    = true

  healthcheck {
    url       = "http://localhost:3284/status"
    interval  = 3
    threshold = 20
  }
}
```

### Linking Tasks to Apps

The connection is established by referencing the app's ID in the `coder_ai_task` resource:

```hcl
resource "coder_ai_task" "main" {
  sidebar_app {
    id = coder_app.agentapi_web.id  # This links the task to the app
  }
}
```

---

## The AgentAPI Module

### What is AgentAPI?

AgentAPI is a service that:
1. Provides a web-based chat interface
2. Manages communication with AI coding agents (Claude, GPT, etc.)
3. Reports task status back to Coder
4. Handles message passing between the user and the AI agent

### Module Structure

The AgentAPI module is available at `registry.coder.com/coder/agentapi/coder`.

**Key files:**
- `main.tf` - Terraform configuration
- `scripts/main.sh` - Installation and startup script
- `scripts/agentapi-wait-for-start.sh` - Health check script

### Key Components

```hcl
# From registry/coder/modules/agentapi/main.tf

# 1. Installation script
resource "coder_script" "agentapi" {
  agent_id     = var.agent_id
  display_name = "Install and start AgentAPI"
  script       = <<-EOT
    # Installs AgentAPI and starts the service
  EOT
  run_on_start = true
}

# 2. Web app for the chat interface
resource "coder_app" "agentapi_web" {
  slug         = var.web_app_slug
  display_name = var.web_app_display_name
  agent_id     = var.agent_id
  url          = "http://localhost:${var.agentapi_port}/"
  icon         = var.web_app_icon
  subdomain    = var.agentapi_subdomain

  healthcheck {
    url       = "http://localhost:${var.agentapi_port}/status"
    interval  = 3
    threshold = 20
  }
}

# 3. Optional CLI app for terminal access
resource "coder_app" "agentapi_cli" {
  count        = var.cli_app ? 1 : 0
  slug         = var.cli_app_slug
  display_name = var.cli_app_display_name
  agent_id     = var.agent_id
  command      = "agentapi attach"
}

# 4. Output the app ID for use in coder_ai_task
output "task_app_id" {
  value = coder_app.agentapi_web.id
}
```

---

## Creating Custom AI Task Modules

### Minimum Requirements

To create a custom AI Task module, you need:

1. **A `coder_app` resource** - The web interface for the chat
2. **An output for the app ID** - So templates can reference it
3. **A service running on a port** - The actual chat application
4. **AgentAPI compatibility** - If you want Coder's backend to communicate with your agent

### Example: Custom Chat Module

```hcl
# my-custom-chat/main.tf

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "port" {
  type        = number
  description = "Port for the chat service"
  default     = 8080
}

variable "display_name" {
  type        = string
  description = "Display name for the app"
  default     = "My AI Chat"
}

# Install your custom chat service
resource "coder_script" "install_chat" {
  agent_id     = var.agent_id
  display_name = "Install Custom Chat"
  script       = <<-EOT
    #!/bin/bash
    set -e

    # Install your chat service here
    # Example: Download and run your custom chat app
    curl -fsSL https://example.com/my-chat-app | bash

    # Start the service
    my-chat-app serve --port ${var.port} &
  EOT
  run_on_start = true
}

# Define the web app
resource "coder_app" "chat_web" {
  slug         = "custom-chat"
  display_name = var.display_name
  agent_id     = var.agent_id
  url          = "http://localhost:${var.port}/"
  icon         = "/icon/chat.svg"
  subdomain    = true

  healthcheck {
    url       = "http://localhost:${var.port}/health"
    interval  = 5
    threshold = 10
  }
}

# IMPORTANT: Export the app ID for coder_ai_task
output "task_app_id" {
  value       = coder_app.chat_web.id
  description = "The ID of the chat app, for use with coder_ai_task"
}
```

**Usage in a template:**

```hcl
module "my_chat" {
  source   = "./my-custom-chat"
  agent_id = coder_agent.main.id
}

resource "coder_ai_task" "main" {
  sidebar_app {
    id = module.my_chat.task_app_id
  }
}
```

---

## Real-World Example: OpenCode Module

The OpenCode module (`registry.coder.com/coder-labs/opencode/coder`) demonstrates a complete AI Task implementation.

### Module Usage

```hcl
module "opencode" {
  source       = "registry.coder.com/coder-labs/opencode/coder"
  version      = "1.0.0"
  agent_id     = coder_agent.main.id
  workdir      = "/home/coder/project"
  report_tasks = true
}

resource "coder_ai_task" "main" {
  sidebar_app {
    id = module.opencode.task_app_id
  }
}
```

### How OpenCode Works

1. **Wraps the AgentAPI module:**
   ```hcl
   module "agentapi" {
     source               = "registry.coder.com/coder/agentapi/coder"
     version              = "2.0.0"
     agent_id             = var.agent_id
     web_app_slug         = "opencode"
     web_app_display_name = var.web_app_display_name
     # ... other configuration
   }
   ```

2. **Installs OpenCode CLI:**
   ```bash
   # From scripts/install.sh
   curl -fsSL https://opencode.ai/install | bash
   ```

3. **Starts OpenCode with AgentAPI:**
   ```bash
   # From scripts/start.sh
   opencode --prompt "$AI_PROMPT" --workdir "$WORKDIR"
   ```

4. **Exports the app ID:**
   ```hcl
   output "task_app_id" {
     value = module.agentapi.task_app_id
   }
   ```

### Key Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `agent_id` | The Coder agent ID | Required |
| `workdir` | Working directory for OpenCode | Required |
| `report_tasks` | Enable status reporting | `true` |
| `ai_prompt` | Initial prompt for the AI | `""` |
| `install_agentapi` | Install AgentAPI | `true` |
| `agentapi_version` | AgentAPI version | `v0.11.2` |
| `subdomain` | Use subdomain for app | `false` |

---

## Customization Options

### Changing the Chat UI

The chat UI is entirely controlled by the service running on the app's URL. To customize:

1. **Replace the service**: Point `coder_app.url` to your own service
2. **Modify the existing service**: Fork AgentAPI and customize the frontend
3. **Use a different agent**: Configure OpenCode/Claude Code/etc. with different settings

### Changing the App Appearance

Modify these `coder_app` attributes:
- `display_name` - Name shown in the UI
- `icon` - Icon path (e.g., `/icon/custom.svg`)
- `slug` - URL-friendly identifier
- `group` - Group apps together in the UI

### Adding Additional Apps

You can add more apps alongside the chat:

```hcl
resource "coder_app" "preview" {
  slug         = "preview"
  display_name = "Preview"
  agent_id     = coder_agent.main.id
  url          = "http://localhost:3000/"
  icon         = "/icon/browser.svg"
  subdomain    = true
}
```

These will appear in the right panel of the Task page.

---

## Troubleshooting

### "Template does not have a valid coder_ai_task resource"

**Cause**: The template doesn't include a `coder_ai_task` resource.

**Solution**: Add the resource to your template:
```hcl
resource "coder_ai_task" "main" {
  sidebar_app {
    id = module.opencode.task_app_id
  }
}
```

### "Chat app not found"

**Cause**: The `workspace_app_id` on the task doesn't match any app in the workspace.

**Solution**: Ensure:
1. The `coder_ai_task.sidebar_app.id` references a valid `coder_app`
2. The app is associated with the correct agent
3. The workspace has finished building

### App shows "unhealthy"

**Cause**: The healthcheck URL is not responding.

**Solution**:
1. SSH into the workspace
2. Check if the service is running: `curl http://localhost:3284/status`
3. Check logs: `cat /tmp/coder-agent.log`

### Iframe shows blank or error

**Cause**: Wildcard hostname not configured.

**Solution**: Configure `CODER_WILDCARD_ACCESS_URL` or set `subdomain = false` on the app.

---

## References

- [Coder AI Tasks Documentation](https://coder.com/docs/ai-coder/tasks)
- [AgentAPI SDK](https://github.com/coder/agentapi-sdk-go)
- [Terraform Provider Coder](https://registry.terraform.io/providers/coder/coder/latest/docs)
- [Coder Registry - AgentAPI Module](https://registry.coder.com/modules/agentapi)
- [Coder Registry - OpenCode Module](https://registry.coder.com/modules/opencode)
