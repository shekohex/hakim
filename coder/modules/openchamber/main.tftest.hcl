run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder/project"
  }

  assert {
    condition     = var.install_openchamber == true
    error_message = "OpenChamber installation should be enabled by default"
  }

  assert {
    condition     = var.openchamber_version == "latest"
    error_message = "Default OpenChamber version should be 'latest'"
  }

  assert {
    condition     = var.port == 6904
    error_message = "Default port should be 6904"
  }

  assert {
    condition     = local.app_slug == "openchamber"
    error_message = "App slug should be 'openchamber'"
  }

  assert {
    condition     = local.module_dir_name == ".openchamber-module"
    error_message = "Module dir name should be '.openchamber-module'"
  }
}

run "workdir_trailing_slash_trimmed" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder/project/"
  }

  assert {
    condition     = local.workdir == "/home/coder/project"
    error_message = "Workdir should be trimmed of trailing slash"
  }
}

run "ui_password_configuration" {
  command = plan

  variables {
    agent_id             = "test-agent"
    workdir              = "/home/coder/project"
    ui_password          = "secret"
    port                 = 7000
    subdomain            = false
    web_app_display_name = "OpenChamber UI"
  }

  assert {
    condition     = var.ui_password == "secret"
    error_message = "UI password should be set correctly"
  }

  assert {
    condition     = var.port == 7000
    error_message = "Port should be set correctly"
  }

  assert {
    condition     = var.subdomain == false
    error_message = "Subdomain should be set correctly"
  }

  assert {
    condition     = var.web_app_display_name == "OpenChamber UI"
    error_message = "Custom display name should be set"
  }
}
