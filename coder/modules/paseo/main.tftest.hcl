run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = local.app_slug == "paseo"
    error_message = "App slug should be 'paseo'"
  }

  assert {
    condition     = local.port == 6767
    error_message = "Paseo port should be 6767"
  }

  assert {
    condition     = local.icon == "https://app.paseo.sh/apple-touch-icon.png"
    error_message = "Paseo should use the app.paseo.sh Apple touch icon"
  }

  assert {
    condition     = var.enabled == true
    error_message = "Paseo should be enabled by default"
  }

  assert {
    condition     = length(coder_app.paseo) == 1
    error_message = "Paseo app should exist when enabled"
  }

  assert {
    condition     = coder_app.paseo[0].share == "owner"
    error_message = "Paseo app should require workspace owner authentication"
  }

  assert {
    condition     = coder_app.paseo[0].subdomain == true
    error_message = "Paseo app should use a subdomain"
  }
}

run "disabled_hides_app" {
  command = plan

  variables {
    agent_id = "test-agent"
    enabled  = false
  }

  assert {
    condition     = length(coder_app.paseo) == 0
    error_message = "Paseo app should not exist when disabled"
  }
}
