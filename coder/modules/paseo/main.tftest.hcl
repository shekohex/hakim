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

  assert {
    condition     = length(regexall("--relay --relay-use-tls", local.install_script)) == 1
    error_message = "Paseo service should enable the TLS relay"
  }

  assert {
    condition     = length(regexall("--no-relay", local.install_script)) == 0
    error_message = "Paseo service should not disable the relay"
  }

  assert {
    condition     = length(regexall("\\.local/bin:.*\\.npm-global/bin:.*\\.local/share/pnpm:.*\\.local/share/vite-plus/bin:", local.install_script)) == 1
    error_message = "Paseo service should expose user-managed command directories"
  }

  assert {
    condition     = length(regexall("\\.local/share/mise/shims:.*\\.cargo/bin:.*\\.dotnet/tools:.*go/bin:.*\\.opencode/bin:.*\\.config/composer/vendor/bin:.*nix/var/nix/profiles/default/bin:.*usr/local/share/mise/shims:", local.install_script)) == 1
    error_message = "Paseo service should expose Hakim toolchain directories"
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
