run "enabled_by_default" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.enabled && coder_script.avahi.run_on_start
    error_message = "Avahi should be enabled and configured on every workspace start"
  }

  assert {
    condition     = coder_script.avahi.agent_id == "test-agent"
    error_message = "Avahi should run on the supplied agent"
  }
}

run "can_disable" {
  command = plan

  variables {
    agent_id = "test-agent"
    enabled  = false
  }

  assert {
    condition     = coder_script.avahi.run_on_start && strcontains(coder_script.avahi.script, "if [ 'false' != 'true' ]; then")
    error_message = "Disabling mDNS should still run the script to stop the existing service"
  }
}
