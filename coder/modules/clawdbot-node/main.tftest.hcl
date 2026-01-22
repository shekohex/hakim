run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.install_clawdbot == true
    error_message = "Clawdbot installation should be enabled by default"
  }

  assert {
    condition     = var.clawdbot_version == "latest"
    error_message = "Default Clawdbot version should be 'latest'"
  }

  assert {
    condition     = var.bridge_port == 18790
    error_message = "Default bridge port should be 18790"
  }

  assert {
    condition     = local.app_slug == "clawdbot-node"
    error_message = "App slug should be 'clawdbot-node'"
  }
}

run "bridge_config_passed" {
  command = plan

  variables {
    agent_id               = "test-agent"
    bridge_host            = "gateway.internal"
    bridge_port            = 12345
    bridge_tls             = true
    bridge_tls_fingerprint = "deadbeef"
    display_name           = "Coder WS"
    gateway_ws_url         = "ws://gateway.internal:18789"
    gateway_token          = "token"
    auto_approve_pairing   = true
  }

  assert {
    condition     = var.bridge_host == "gateway.internal"
    error_message = "Bridge host should be set"
  }

  assert {
    condition     = var.auto_approve_pairing == true
    error_message = "Auto approve pairing should be enabled"
  }
}
