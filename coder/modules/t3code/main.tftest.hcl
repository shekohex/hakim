run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = local.app_slug == "t3"
    error_message = "App slug should be 't3'"
  }

  assert {
    condition     = var.port == 3157 && coder_app.t3[0].url == "http://localhost:3157/"
    error_message = "T3 Code should use port 3157 by default"
  }

  assert {
    condition     = local.icon == "https://t3.codes/apple-touch-icon.png"
    error_message = "T3 Code should use the t3.codes icon"
  }

  assert {
    condition     = var.enabled == true
    error_message = "T3 Code should be enabled by default"
  }

  assert {
    condition     = length(coder_app.t3) == 1
    error_message = "T3 Code app should exist when enabled"
  }

  assert {
    condition     = coder_app.t3[0].share == "public"
    error_message = "T3 Code app should be public"
  }

  assert {
    condition     = coder_app.t3[0].subdomain == true
    error_message = "T3 Code app should use a subdomain"
  }
}

run "custom_port" {
  command = plan

  variables {
    agent_id = "test-agent"
    port     = 4321
  }

  assert {
    condition     = coder_app.t3[0].url == "http://localhost:4321/" && one(coder_app.t3[0].healthcheck).url == "http://localhost:4321/"
    error_message = "App and healthcheck should use the configured port"
  }

  assert {
    condition     = strcontains(coder_script.t3code_install.script, "ARG_PORT='4321'") && coder_script.t3code_install.run_on_start
    error_message = "Workspace startup should configure the service with the custom port"
  }
}

run "reject_zero_port" {
  command = plan

  variables {
    agent_id = "test-agent"
    port     = 0
  }

  expect_failures = [var.port]
}

run "reject_out_of_range_port" {
  command = plan

  variables {
    agent_id = "test-agent"
    port     = 65536
  }

  expect_failures = [var.port]
}

run "reject_fractional_port" {
  command = plan

  variables {
    agent_id = "test-agent"
    port     = 3157.5
  }

  expect_failures = [var.port]
}

run "disabled_hides_app" {
  command = plan

  variables {
    agent_id = "test-agent"
    enabled  = false
  }

  assert {
    condition     = length(coder_app.t3) == 0
    error_message = "T3 Code app should not exist when disabled"
  }
}
