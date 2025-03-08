# Terraform config for managing GitHub repositories

terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = ">= 5.0"
    }
  }
}

# VARIABLES
# stored as environment variables on my system
# export TF_var...
variable "github_pat" {
  type        = string
  description = "GitHub Personal Access Token"
  sensitive   = true
}

variable "discord_webhook_url" {
  type        = string
  description = "Discord webhook URL"
  sensitive   = true
}

# Configures repositories providers
provider "github" {
  token = var.github_pat
  owner = "Practical-DevOps-GitHub"
}

resource "github_repository" "repo" {
  name = "github-terraform-task-artur-vol"
}

# Assignes user `softservedata` as a collaborator
resource "github_repository_collaborator" "repo_collaborator" {
  repository = github_repository.repo.name
  username   = "softservedata"
  permission = "admin"
}

# FILES
data "local_file" "pr_template" {
  filename = "${path.module}/pull_request_template.md"
}

data "local_file" "discord_workflow" {
  filename = "${path.module}/discord_workflow.yml"
}

# A pull request template configuration
resource "github_repository_file" "pull_request_template" {
  repository     = github_repository.repo.name
  file           = ".github/pull_request_template.md"
  content        = data.local_file.pr_template.content
  branch         = "main"
  commit_message = "Add Pull Request template"
}

# Assign the user `softservedata` as the code owner for all the files in the `main` branch
# *I couldn't find a built-in way to do this in the provider, so I did it using a file
resource "github_repository_file" "codeowners" {
  repository     = github_repository.repo.name
  file           = ".github/CODEOWNERS"
  content        = "* @softservedata"
  branch         = "main"
  commit_message = "Add CODEOWNERS file"
}

# Discord workflow configuration (used for notifications)
# *I couldn't implement notifications within the GitHub provider 
# because I kept getting an error saying that the message body sent
# to the Discord server was empty, and the provider didn’t seem to offer a way to fix it
resource "github_repository_file" "discord_workflow" {
  repository     = github_repository.repo.name
  file           = ".github/workflows/discord.yml"
  branch         = "main"
  commit_message = "Add Discord notification workflow"
  content        = data.local_file.discord_workflow.content
}

# Create branch
resource "github_branch" "develop" {
  repository    = github_repository.repo.name
  branch        = "develop"
  source_branch = "main"

  # Responsible for creating the develop branch only after files 
  # have been added to main, so it inherits them
  depends_on = [
    github_repository_file.discord_workflow,
    github_repository_file.codeowners,
    github_repository_file.pull_request_template
  ]
}

# and makes that branch default
resource "github_branch_default" "default_branch" {
  repository = github_repository.repo.name
  branch     = github_branch.develop.branch
}

# Protection rules confiduration
# for main branch:
resource "github_branch_protection" "main_protection" {
  repository_id = github_repository.repo.name
  pattern       = "main"

  required_pull_request_reviews {
    required_approving_review_count = 1
    require_code_owner_reviews      = true
  }

  required_status_checks {
    strict   = true
    contexts = []
  }

  enforce_admins = true

  depends_on = [
    github_repository_file.discord_workflow,
    github_repository_file.codeowners,
    github_repository_file.pull_request_template
  ]
}

# and for develop branch:
resource "github_branch_protection" "develop_protection" {
  repository_id = github_repository.repo.name
  pattern       = "develop"

  required_pull_request_reviews {
    required_approving_review_count = 2
  }

  required_status_checks {
    strict   = true
    contexts = []
  }

  enforce_admins = true
}

# Generates deploy key
resource "tls_private_key" "deploy_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Add deploy key to repo
resource "github_repository_deploy_key" "repo_deploy_key" {
  repository = github_repository.repo.name
  title      = "DEPLOY_KEY"
  key        = tls_private_key.deploy_key.public_key_openssh
  read_only  = true
}

# SECRETS
# *Initially, I passed secrets this way because I thought all the required tasks had to be executed within main.tf
# However, I later realized that the variables needed to be created manually, and this approach wasn't particularly secure
# for discord:
resource "github_actions_secret" "discord_webhook_secret" {
  repository      = github_repository.repo.name
  secret_name     = "DISCORD_WEBHOOK_URL"
  plaintext_value = var.discord_webhook_url
}

# personal access token:
resource "github_actions_secret" "pat_secret" {
  repository      = github_repository.repo.name
  secret_name     = "PAT"
  plaintext_value = var.github_pat
}

