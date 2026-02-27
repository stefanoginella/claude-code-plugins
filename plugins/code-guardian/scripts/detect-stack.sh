#!/usr/bin/env bash
# Detect project stack: languages, frameworks, Docker, CI systems
# Outputs JSON to stdout
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

languages=()
frameworks=()
has_docker=false
has_docker_compose=false
ci_systems=()
package_managers=()
iac_tools=()

# ── Language detection ────────────────────────────────────────────────

# JavaScript / TypeScript
if ls ./*.js ./*.ts ./*.jsx ./*.tsx src/**/*.js src/**/*.ts 2>/dev/null | head -1 &>/dev/null || \
   [[ -f package.json ]]; then
  if [[ -f tsconfig.json ]] || [[ -f tsconfig.*.json ]] 2>/dev/null; then
    languages+=("typescript")
  fi
  languages+=("javascript")
  # Package managers
  [[ -f package-lock.json ]] && package_managers+=("npm")
  [[ -f yarn.lock ]] && package_managers+=("yarn")
  [[ -f pnpm-lock.yaml ]] && package_managers+=("pnpm")
  [[ -f bun.lockb ]] || [[ -f bun.lock ]] && package_managers+=("bun")
  # Frameworks
  if [[ -f package.json ]]; then
    grep -q '"next"' package.json 2>/dev/null && frameworks+=("nextjs")
    grep -q '"react"' package.json 2>/dev/null && frameworks+=("react")
    grep -q '"vue"' package.json 2>/dev/null && frameworks+=("vue")
    grep -q '"angular"' package.json 2>/dev/null && frameworks+=("angular")
    grep -q '"express"' package.json 2>/dev/null && frameworks+=("express")
    grep -q '"fastify"' package.json 2>/dev/null && frameworks+=("fastify")
    grep -q '"svelte"' package.json 2>/dev/null && frameworks+=("svelte")
    grep -q '"nuxt"' package.json 2>/dev/null && frameworks+=("nuxt")
    grep -q '"astro"' package.json 2>/dev/null && frameworks+=("astro")
  fi
fi

# Python
if ls ./*.py 2>/dev/null | head -1 &>/dev/null || \
   [[ -f requirements.txt ]] || [[ -f pyproject.toml ]] || [[ -f setup.py ]] || [[ -f Pipfile ]]; then
  languages+=("python")
  [[ -f requirements.txt ]] && package_managers+=("pip")
  [[ -f Pipfile ]] && package_managers+=("pipenv")
  [[ -f poetry.lock ]] && package_managers+=("poetry")
  [[ -f pyproject.toml ]] && grep -q 'build-backend.*hatchling\|build-backend.*flit\|build-backend.*setuptools' pyproject.toml 2>/dev/null && package_managers+=("pyproject")
  # Frameworks
  grep -rql 'from django\|import django' . --include="*.py" 2>/dev/null | head -1 &>/dev/null && frameworks+=("django")
  grep -rql 'from flask\|import flask' . --include="*.py" 2>/dev/null | head -1 &>/dev/null && frameworks+=("flask")
  grep -rql 'from fastapi\|import fastapi' . --include="*.py" 2>/dev/null | head -1 &>/dev/null && frameworks+=("fastapi")
fi

# Go
if [[ -f go.mod ]] || ls ./*.go 2>/dev/null | head -1 &>/dev/null; then
  languages+=("go")
  package_managers+=("go-modules")
fi

# Rust
if [[ -f Cargo.toml ]] || [[ -f Cargo.lock ]]; then
  languages+=("rust")
  package_managers+=("cargo")
fi

# Ruby
if [[ -f Gemfile ]] || [[ -f Rakefile ]] || ls ./*.rb 2>/dev/null | head -1 &>/dev/null; then
  languages+=("ruby")
  package_managers+=("bundler")
  [[ -f config/routes.rb ]] && frameworks+=("rails")
fi

# Java / Kotlin
if [[ -f pom.xml ]] || [[ -f build.gradle ]] || [[ -f build.gradle.kts ]]; then
  if [[ -f build.gradle.kts ]] || find . -name "*.kt" -maxdepth 3 2>/dev/null | head -1 &>/dev/null; then
    languages+=("kotlin")
  fi
  languages+=("java")
  [[ -f pom.xml ]] && package_managers+=("maven")
  [[ -f build.gradle ]] || [[ -f build.gradle.kts ]] && package_managers+=("gradle")
fi

# PHP
if [[ -f composer.json ]] || ls ./*.php 2>/dev/null | head -1 &>/dev/null; then
  languages+=("php")
  package_managers+=("composer")
  grep -q '"laravel/framework"' composer.json 2>/dev/null && frameworks+=("laravel")
fi

# C# / .NET
if ls ./*.csproj ./*.sln 2>/dev/null | head -1 &>/dev/null || [[ -f global.json ]]; then
  languages+=("csharp")
  package_managers+=("nuget")
fi

# ── Docker detection ──────────────────────────────────────────────────
if [[ -f Dockerfile ]] || ls Dockerfile.* ./*.dockerfile 2>/dev/null | head -1 &>/dev/null; then
  has_docker=true
fi
if [[ -f docker-compose.yml ]] || [[ -f docker-compose.yaml ]] || [[ -f compose.yml ]] || [[ -f compose.yaml ]]; then
  has_docker_compose=true
fi

# ── CI detection ──────────────────────────────────────────────────────
[[ -d .github/workflows ]] && ci_systems+=("github-actions")
[[ -f .gitlab-ci.yml ]] && ci_systems+=("gitlab-ci")
[[ -f Jenkinsfile ]] && ci_systems+=("jenkins")
[[ -f .circleci/config.yml ]] && ci_systems+=("circleci")
[[ -f .travis.yml ]] && ci_systems+=("travis")
[[ -f bitbucket-pipelines.yml ]] && ci_systems+=("bitbucket-pipelines")
[[ -f azure-pipelines.yml ]] && ci_systems+=("azure-pipelines")
[[ -d .buildkite ]] && ci_systems+=("buildkite")

# ── IaC detection ─────────────────────────────────────────────────────
# Terraform: look for .tf files
if find . -maxdepth 3 -name "*.tf" 2>/dev/null | grep -q .; then
  iac_tools+=("terraform")
fi
# CloudFormation: look for AWSTemplateFormatVersion in YAML/JSON
if find . -maxdepth 3 \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) -not -path './.git/*' 2>/dev/null | \
   xargs grep -l "AWSTemplateFormatVersion" 2>/dev/null | grep -q .; then
  iac_tools+=("cloudformation")
fi
# Helm: look for Chart.yaml specifically
if find . -maxdepth 3 -name "Chart.yaml" 2>/dev/null | grep -q .; then
  iac_tools+=("helm")
fi
# Kubernetes: look for k8s manifests (apiVersion + kind in same file, not in node_modules or .github)
if find . -maxdepth 3 \( -name "*.yaml" -o -name "*.yml" \) -not -path './.git/*' -not -path './node_modules/*' -not -path './.github/*' 2>/dev/null | \
   xargs grep -l "^apiVersion:" 2>/dev/null | xargs grep -l "^kind:" 2>/dev/null | grep -q .; then
  iac_tools+=("kubernetes")
fi

# ── Output JSON ───────────────────────────────────────────────────────
json_array() {
  local items=("$@")
  if [[ ${#items[@]} -eq 0 ]]; then
    printf '[]'
    return
  fi
  local out="["
  for i in "${!items[@]}"; do
    [[ $i -gt 0 ]] && out+=","
    out+="\"${items[$i]}\""
  done
  out+="]"
  printf '%s' "$out"
}

# Build each field (use ${arr[@]+"${arr[@]}"} to handle empty arrays with set -u)
_lang=$(json_array ${languages[@]+"${languages[@]}"})
_frame=$(json_array ${frameworks[@]+"${frameworks[@]}"})
_pm=$(json_array ${package_managers[@]+"${package_managers[@]}"})
_ci=$(json_array ${ci_systems[@]+"${ci_systems[@]}"})
_iac=$(json_array ${iac_tools[@]+"${iac_tools[@]}"})

printf '{\n'
printf '  "languages": %s,\n' "$_lang"
printf '  "frameworks": %s,\n' "$_frame"
printf '  "packageManagers": %s,\n' "$_pm"
printf '  "docker": %s,\n' "$has_docker"
printf '  "dockerCompose": %s,\n' "$has_docker_compose"
printf '  "ciSystems": %s,\n' "$_ci"
printf '  "iacTools": %s\n' "$_iac"
printf '}\n'
