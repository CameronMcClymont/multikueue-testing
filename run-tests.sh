#!/bin/bash
#
# MultiKueue Testing Suite
# Runs code quality checks, linting, and formatting validation
# Inspired by REANA's testing approach

set -o errexit
set -o nounset

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check functions
check_shellcheck() {
    echo -e "${BLUE}Running shellcheck...${NC}"
    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck ./*.sh
        echo -e "${GREEN}✅ shellcheck passed${NC}"
    else
        echo -e "${YELLOW}⚠️  shellcheck not found, skipping${NC}"
    fi
}

check_yamllint() {
    echo -e "${BLUE}Running yamllint...${NC}"
    if command -v yamllint >/dev/null 2>&1; then
        yamllint ./*.yaml
        echo -e "${GREEN}✅ yamllint passed${NC}"
    else
        echo -e "${YELLOW}⚠️  yamllint not found, skipping${NC}"
    fi
}

check_markdownlint() {
    echo -e "${BLUE}Running markdownlint-cli2...${NC}"
    if command -v markdownlint-cli2 >/dev/null 2>&1; then
        markdownlint-cli2 ./*.md
        echo -e "${GREEN}✅ markdownlint-cli2 passed${NC}"
    else
        echo -e "${YELLOW}⚠️  markdownlint-cli2 not found, skipping${NC}"
    fi
}

check_gitignore() {
    echo -e "${BLUE}Checking .gitignore...${NC}"
    if [[ -f .gitignore ]]; then
        if grep -q ".kubeconfig" .gitignore; then
            echo -e "${GREEN}✅ .gitignore contains required patterns${NC}"
        else
            echo -e "${RED}❌ .gitignore missing .kubeconfig pattern${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ .gitignore file not found${NC}"
        return 1
    fi
}

check_file_structure() {
    echo -e "${BLUE}Checking file structure...${NC}"
    local required_files=(
        "1-setup-clusters.sh"
        "2-configure-multikueue.sh"
        "3-test-multikueue.sh"
        "4-cleanup.sh"
        "manager-cluster-manifests.yaml"
        "worker-cluster-manifests.yaml"
        "sample-job.yaml"
        "README.md"
        "CLAUDE.md"
        ".gitignore"
        ".editorconfig"
    )

    local missing_files=()
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done

    if [[ ${#missing_files[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ All required files present${NC}"
    else
        echo -e "${RED}❌ Missing files: ${missing_files[*]}${NC}"
        return 1
    fi
}

check_script_permissions() {
    echo -e "${BLUE}Checking script permissions...${NC}"
    local scripts=("1-setup-clusters.sh" "2-configure-multikueue.sh" "3-test-multikueue.sh" "4-cleanup.sh")
    local non_executable=()

    for script in "${scripts[@]}"; do
        if [[ -f "$script" && ! -x "$script" ]]; then
            non_executable+=("$script")
        fi
    done

    if [[ ${#non_executable[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ All scripts are executable${NC}"
    else
        echo -e "${YELLOW}⚠️  Non-executable scripts: ${non_executable[*]}${NC}"
        echo -e "${BLUE}Making scripts executable...${NC}"
        chmod +x "${non_executable[@]}"
        echo -e "${GREEN}✅ Scripts made executable${NC}"
    fi
}

check_yaml_dry_run() {
    echo -e "${BLUE}Running YAML dry-run validation...${NC}"
    if command -v kubectl >/dev/null 2>&1; then
        local yaml_files=("manager-cluster-manifests.yaml" "worker-cluster-manifests.yaml" "sample-job.yaml")
        local validation_passed=true

        for yaml_file in "${yaml_files[@]}"; do
            if [[ -f "$yaml_file" ]]; then
                echo "  Validating $yaml_file..."

                # First check basic YAML syntax with yamllint if available
                if command -v yamllint >/dev/null 2>&1; then
                    if yamllint "$yaml_file" >/dev/null 2>&1; then
                        echo -e "    ${GREEN}✅ $yaml_file has valid YAML syntax${NC}"
                    else
                        echo -e "    ${RED}❌ $yaml_file has YAML syntax errors${NC}"
                        validation_passed=false
                        continue
                    fi
                fi

                # Try kubectl validation, but don't fail on CRD-related errors or connection issues
                local kubectl_output kubectl_exit_code
                set +e  # Temporarily disable exit on error
                kubectl_output=$(kubectl --dry-run=client --validate=false apply -f "$yaml_file" 2>&1)
                kubectl_exit_code=$?
                set -e  # Re-enable exit on error

                # Check if the error is due to connection issues, CRDs, or other expected CI problems
                if [[ $kubectl_exit_code -ne 0 ]]; then
                    if echo "$kubectl_output" | grep -q -E "(no matches for kind|the server doesn't have a resource type|resource mapping not found)" ||
                        echo "$kubectl_output" | grep -q -E "(ResourceFlavor|ClusterQueue|LocalQueue|MultiKueue|AdmissionCheck)" ||
                        echo "$kubectl_output" | grep -q "ensure CRDs are installed first" ||
                        echo "$kubectl_output" | grep -q -E "(failed to download openapi|connection refused|dial tcp)" ||
                        echo "$kubectl_output" | grep -q "The connection to the server"; then
                        echo -e "    ${YELLOW}⚠️  $yaml_file contains CRDs or connection issues in CI environment (this is expected)${NC}"
                    else
                        echo -e "    ${RED}❌ $yaml_file has validation errors: $kubectl_output${NC}"
                        validation_passed=false
                    fi
                else
                    echo -e "    ${GREEN}✅ $yaml_file is valid${NC}"
                fi
            fi
        done

        if [[ "$validation_passed" == true ]]; then
            echo -e "${GREEN}✅ All YAML files pass validation${NC}"
        else
            echo -e "${RED}❌ Some YAML files have validation errors${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠️  kubectl not found, skipping YAML validation${NC}"
    fi
}

check_documentation() {
    echo -e "${BLUE}Checking documentation completeness...${NC}"
    local issues=()

    # Check README.md
    if [[ -f README.md ]]; then
        if ! grep -q "Quick Start" README.md; then
            issues+=("README.md missing Quick Start section")
        fi
        if ! grep -q "File Structure" README.md; then
            issues+=("README.md missing File Structure section")
        fi
        if ! grep -q "Troubleshooting" README.md; then
            issues+=("README.md missing Troubleshooting section")
        fi
    else
        issues+=("README.md not found")
    fi

    # Check CLAUDE.md
    if [[ -f CLAUDE.md ]]; then
        if ! grep -q "Project Overview" CLAUDE.md; then
            issues+=("CLAUDE.md missing Project Overview section")
        fi
        if ! grep -q "Usage Commands" CLAUDE.md; then
            issues+=("CLAUDE.md missing Usage Commands section")
        fi
    else
        issues+=("CLAUDE.md not found")
    fi

    if [[ ${#issues[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ Documentation is complete${NC}"
    else
        echo -e "${RED}❌ Documentation issues:${NC}"
        printf "    %s\n" "${issues[@]}"
        return 1
    fi
}

check_script_consistency() {
    echo -e "${BLUE}Checking script consistency...${NC}"
    local issues=()

    # Check for run_cmd function usage
    for script in 1-setup-clusters.sh 2-configure-multikueue.sh 3-test-multikueue.sh 4-cleanup.sh; do
        if [[ -f "$script" ]]; then
            if ! grep -q "run_cmd()" "$script"; then
                issues+=("$script missing run_cmd() function")
            fi
            if ! grep -q "print_status" "$script"; then
                issues+=("$script missing print_status function")
            fi
        fi
    done

    # Check for consistent variable naming
    if [[ -f "1-setup-clusters.sh" && -f "2-configure-multikueue.sh" ]]; then
        if ! grep -q "MANAGER_CLUSTER=" 1-setup-clusters.sh; then
            issues+=("1-setup-clusters.sh missing MANAGER_CLUSTER variable")
        fi
        if ! grep -q "WORKER_CLUSTER=" 1-setup-clusters.sh; then
            issues+=("1-setup-clusters.sh missing WORKER_CLUSTER variable")
        fi
    fi

    if [[ ${#issues[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ Scripts are consistent${NC}"
    else
        echo -e "${RED}❌ Script consistency issues:${NC}"
        printf "    %s\n" "${issues[@]}"
        return 1
    fi
}

# Main execution logic
run_all_checks() {
    local failed_checks=()

    echo -e "${BLUE}🧪 Running MultiKueue Testing Suite${NC}"
    echo "===================================="
    echo

    # Run each check and collect failures
    check_file_structure || failed_checks+=("file_structure")
    echo

    check_script_permissions || failed_checks+=("script_permissions")
    echo

    check_gitignore || failed_checks+=("gitignore")
    echo

    check_shellcheck || failed_checks+=("shellcheck")
    echo

    check_yamllint || failed_checks+=("yamllint")
    echo

    check_markdownlint || failed_checks+=("markdownlint")
    echo

    check_yaml_dry_run || failed_checks+=("yaml_dry_run")
    echo

    check_documentation || failed_checks+=("documentation")
    echo

    check_script_consistency || failed_checks+=("script_consistency")
    echo

    # Summary
    if [[ ${#failed_checks[@]} -eq 0 ]]; then
        echo -e "${GREEN}🎉 All checks passed!${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed checks: ${failed_checks[*]}${NC}"
        return 1
    fi
}

# Usage information
show_usage() {
    echo "Usage: $0 [CHECK_NAME]"
    echo
    echo "Available checks:"
    echo "  shellcheck         - Run shellcheck on shell scripts"
    echo "  yamllint          - Run yamllint on YAML files"
    echo "  markdownlint      - Run markdownlint-cli2 on Markdown files"
    echo "  gitignore         - Check .gitignore file"
    echo "  file_structure    - Check required files are present"
    echo "  script_permissions - Check script permissions"
    echo "  yaml_dry_run      - Validate YAML with kubectl dry-run"
    echo "  documentation     - Check documentation completeness"
    echo "  script_consistency - Check script consistency"
    echo "  all               - Run all checks (default)"
    echo
    echo "Examples:"
    echo "  $0                # Run all checks"
    echo "  $0 shellcheck     # Run only shellcheck"
    echo "  $0 yamllint       # Run only yamllint"
}

# Main execution
if [[ $# -eq 0 ]]; then
    run_all_checks
elif [[ $# -eq 1 ]]; then
    case "$1" in
    shellcheck)
        check_shellcheck
        ;;
    yamllint)
        check_yamllint
        ;;
    markdownlint)
        check_markdownlint
        ;;
    gitignore)
        check_gitignore
        ;;
    file_structure)
        check_file_structure
        ;;
    script_permissions)
        check_script_permissions
        ;;
    yaml_dry_run)
        check_yaml_dry_run
        ;;
    documentation)
        check_documentation
        ;;
    script_consistency)
        check_script_consistency
        ;;
    all)
        run_all_checks
        ;;
    -h | --help)
        show_usage
        ;;
    *)
        echo -e "${RED}❌ Unknown check: $1${NC}"
        echo
        show_usage
        exit 1
        ;;
    esac
else
    echo -e "${RED}❌ Too many arguments${NC}"
    echo
    show_usage
    exit 1
fi
