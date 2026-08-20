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
    condition     = local.port == 1337
    error_message = "T3 Code port should be 1337"
  }

  assert {
    condition     = local.icon == "https://t3.codes/apple-touch-icon.png"
    error_message = "T3 Code should use the t3.codes icon"
  }

  assert {
    condition     = coder_app.t3.share == "public"
    error_message = "T3 Code app should be public"
  }

  assert {
    condition     = coder_app.t3.subdomain == true
    error_message = "T3 Code app should use a subdomain"
  }
}
