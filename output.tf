# ============================================================================
# output.tf — Project summary exposed via Terraform
# ============================================================================
# This file is the single source of truth for the project metadata that the
# AI Review Agent framework advertises. It is consumed by downstream infra
# code, dashboards, and documentation generators.
# ============================================================================

output "project_summary" {
  value = {
    application_name = "UserApi"
    ai_framework     = "Provider Agnostic AI Review Agent"

    supported_providers = [
      "Claude",
      "NVIDIA",
      "Ollama",
      "OpenAI",
      "Azure OpenAI",
    ]

    pipeline_stages = [
      "Build",
      "Test",
      "Trivy Scan",
      "AI Review",
      "Deploy",
    ]
  }
  description = "High-level summary of the project, the AI review framework, the supported AI providers, and the CI/CD pipeline stages."
}