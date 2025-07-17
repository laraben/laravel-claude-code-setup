#!/bin/bash

# Laravel Claude Code Setup Script
# Automatically configures Claude Code with MCP servers for Laravel development
# Author: Laravel Developer
# Version: 2.1 - GitLab integration added

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in a Laravel project
check_laravel_project() {
    if [ ! -f "artisan" ] || [ ! -f "composer.json" ]; then
        print_error "This doesn't appear to be a Laravel project directory!"
        print_error "Please run this script from your Laravel project root."
        exit 1
    fi
    
    if [ ! -f ".env" ]; then
        print_error ".env file not found! Please ensure your Laravel project is properly set up."
        exit 1
    fi
    
    print_success "Laravel project detected!"
}



# Better interactive detection that handles curl pipe correctly
can_interact_with_user() {
    # Check if we have a controlling terminal (even if stdin is piped)
    if [ -t 1 ] && [ -t 2 ]; then
        # stdout and stderr are terminals
        # Check if we're NOT in a true non-interactive environment
        if [ -z "$CI" ] && [ -z "$GITHUB_ACTIONS" ] && [ -z "$JENKINS_URL" ]; then
            # Try to access the controlling terminal directly
            if [ -e /dev/tty ]; then
                return 0  # We can interact with the user
            fi
        fi
    fi
    
    return 1  # Cannot interact with user
}

# Helper function to read input from controlling terminal
read_from_user() {
    local prompt="$1"
    local variable_name="$2"
    
    if can_interact_with_user; then
        # Read from controlling terminal instead of stdin
        printf "%s" "$prompt" > /dev/tty
        read -r "$variable_name" < /dev/tty
        return 0
    else
        return 1
    fi
}

# Check GitHub authentication and collect tokens if needed
collect_tokens() {
    print_status "Checking GitHub authentication..."
    echo ""
    
    # Check if GITHUB_TOKEN is already set in environment
    if [ -n "$GITHUB_TOKEN" ]; then
        print_success "Using GITHUB_TOKEN from environment: ${GITHUB_TOKEN:0:8}..."
        GITHUB_AUTH_METHOD="token"
        
        # Ask if user wants to update token
        if can_interact_with_user; then
            echo ""
            local update_token
            if read_from_user "Do you want to update this GitHub token? (y/n): " update_token; then
                if [ "$update_token" = "y" ] || [ "$update_token" = "yes" ]; then
                    GITHUB_TOKEN=""  # Clear the token to prompt for a new one
                    print_status "Please provide the new GitHub token..."
                    
                    # Actually prompt for the new token
                    local new_github_token
                    if read_from_user "Enter your new GitHub Personal Access Token: " new_github_token; then
                        if [ ! -z "$new_github_token" ]; then
                            GITHUB_TOKEN="$new_github_token"
                            print_success "GitHub token updated successfully!"
                        else
                            print_warning "No token provided - keeping original token"
                            # We need to restore the original token here
                            # But since we cleared it, we'll need to get it from config again
                        fi
                    else
                        print_status "Could not read new token - keeping original"
                    fi
                else
                    print_status "Keeping existing GitHub token"
                fi
            else
                print_status "Could not read input - keeping existing token"
            fi
        else
            print_status "Non-interactive environment - keeping existing GitHub token"
        fi
    fi
    
    # Check if token is configured in Claude config file
    CONFIG_FILE="$HOME/.claude.json"
    if [ -z "$GITHUB_TOKEN" ] && [ -f "$CONFIG_FILE" ]; then
        # Check for existing token in global config
        EXISTING_TOKEN=""
        if command -v jq &> /dev/null; then
            EXISTING_TOKEN=$(jq -r '.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
        fi
        
        if [ ! -z "$EXISTING_TOKEN" ] && [ "$EXISTING_TOKEN" != "null" ] && [ "$EXISTING_TOKEN" != "empty" ]; then
            print_success "Found existing GitHub token in Claude config: ${EXISTING_TOKEN:0:8}..."
            GITHUB_TOKEN="$EXISTING_TOKEN"
            GITHUB_AUTH_METHOD="token"
            
            # Ask if user wants to update token
            if can_interact_with_user; then
                echo ""
                local update_existing
                if read_from_user "Do you want to update this GitHub token? (y/n): " update_existing; then
                    if [ "$update_existing" = "y" ] || [ "$update_existing" = "yes" ]; then
                        print_status "Please provide the new GitHub token..."
                        
                        # Actually prompt for the new token
                        local new_github_token
                        if read_from_user "Enter your new GitHub Personal Access Token: " new_github_token; then
                            if [ ! -z "$new_github_token" ]; then
                                GITHUB_TOKEN="$new_github_token"
                                print_success "GitHub token updated successfully!"
                            else
                                print_warning "No token provided - keeping existing token"
                                # GITHUB_TOKEN already has the existing token
                            fi
                        else
                            print_status "Could not read new token - keeping existing"
                        fi
                    else
                        print_status "Keeping existing GitHub token"
                    fi
                else
                    print_status "Could not read input - keeping existing token"
                fi
            else
                print_status "Non-interactive environment - keeping existing GitHub token"
            fi
        fi
    fi
    
    # Continue with GitHub SSH detection logic if no token found...
    if [ -z "$GITHUB_TOKEN" ]; then
        # Test SSH authentication with GitHub
        if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
            print_success "GitHub SSH authentication detected!"
            print_status "However, for MCP integration, a Personal Access Token is recommended for private repositories."
            
            # Ask for choice in interactive mode
            if can_interact_with_user; then
                echo ""
                echo "Choose GitHub authentication method:"
                echo "1) Use SSH (works for public repos, limited for private repos in MCP)"
                echo "2) Provide Personal Access Token (recommended for full private repo access)"
                local auth_choice
                if read_from_user "Enter choice (1 or 2): " auth_choice; then
                    if [ "$auth_choice" = "2" ]; then
                        GITHUB_AUTH_METHOD="token"
                        local attempts=0
                        while [ -z "$GITHUB_TOKEN" ] && [ $attempts -lt 3 ]; do
                            echo ""
                            print_status "To create a GitHub Personal Access Token:"
                            echo "1. Go to GitHub.com → Settings → Developer settings → Personal access tokens → Tokens (classic)"
                            echo "2. Click 'Generate new token (classic)'"
                            echo "3. Select scopes: repo, read:user, user:email"
                            echo "4. Copy the generated token"
                            echo ""
                            local github_token
                            if read_from_user "Enter your GitHub Personal Access Token (or 'skip'): " github_token; then
                                if [ "$github_token" = "skip" ]; then
                                    GITHUB_TOKEN=""
                                    GITHUB_AUTH_METHOD="none"
                                    print_warning "Skipping GitHub MCP integration"
                                    break
                                elif [ ! -z "$github_token" ]; then
                                    GITHUB_TOKEN="$github_token"
                                    print_success "GitHub token configured!"
                                    break
                                else
                                    print_warning "Token is required for GitHub MCP integration!"
                                    attempts=$((attempts + 1))
                                fi
                            else
                                print_status "Could not read input - skipping GitHub integration"
                                GITHUB_AUTH_METHOD="none"
                                break
                            fi
                        done
                    else
                        GITHUB_AUTH_METHOD="ssh"
                        print_warning "Using SSH authentication - private repository access may be limited"
                    fi
                else
                    print_status "Could not read input - using SSH authentication"
                    GITHUB_AUTH_METHOD="ssh"
                fi
            else
                GITHUB_AUTH_METHOD="ssh"
                print_warning "Non-interactive mode - using SSH authentication"
            fi
        else
            print_warning "No GitHub SSH authentication detected"
            GITHUB_AUTH_METHOD="token"
            
            # Check if truly interactive
            if ! can_interact_with_user; then
                print_error "This script requires a GitHub token for GitHub MCP integration."
                print_error "Please set the GITHUB_TOKEN environment variable and try again:"
                echo ""
                echo "export GITHUB_TOKEN=your_token_here"
                echo "curl -fsSL https://your-script-url | bash"
                echo ""
                exit 1
            fi
            
            # Interactive token collection
            local attempts=0
            while [ -z "$GITHUB_TOKEN" ] && [ $attempts -lt 3 ]; do
                echo ""
                print_status "To create a GitHub Personal Access Token:"
                echo "1. Go to GitHub.com → Settings → Developer settings → Personal access tokens → Tokens (classic)"
                echo "2. Click 'Generate new token (classic)'"
                echo "3. Select scopes: repo, read:user, user:email"
                echo "4. Copy the generated token"
                echo ""
                local github_token
                if read_from_user "Enter your GitHub Personal Access Token (or 'skip'): " github_token; then
                    if [ "$github_token" = "skip" ]; then
                        GITHUB_TOKEN=""
                        GITHUB_AUTH_METHOD="none"
                        print_warning "Skipping GitHub MCP integration"
                        break
                    elif [ ! -z "$github_token" ]; then
                        GITHUB_TOKEN="$github_token"
                        print_success "GitHub token configured!"
                        break
                    else
                        print_warning "Token is required for GitHub MCP integration!"
                        attempts=$((attempts + 1))
                    fi
                else
                    print_status "Could not read input - skipping GitHub integration"
                    GITHUB_AUTH_METHOD="none"
                    break
                fi
            done
        fi
    fi
    
    # Get GitHub repository information if we have authentication
    if [ "$GITHUB_AUTH_METHOD" != "none" ]; then
        # Try to detect current repository from git remote
        if command -v git &> /dev/null && [ -d ".git" ]; then
            # Extract owner/repo from git remote URL
            REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
            if [ ! -z "$REMOTE_URL" ]; then
                # Parse GitHub repository from remote URL
                if echo "$REMOTE_URL" | grep -q "github.com"; then
                    # Extract owner/repo from various URL formats
                    DETECTED_REPO=$(echo "$REMOTE_URL" | sed -E 's|.*github\.com[:/]([^/]+/[^/]+)(\.git)?.*|\1|' | sed 's|\.git$||')
                    if [ ! -z "$DETECTED_REPO" ]; then
                        print_success "Detected GitHub repository: $DETECTED_REPO"
                        GITHUB_REPO="$DETECTED_REPO"
                    fi
                fi
            fi
        fi
        
        # Ask for repository if not detected or if user wants to specify different one
        if can_interact_with_user; then
            if [ ! -z "$GITHUB_REPO" ]; then
                local repo_choice
                if read_from_user "Use detected repository '$GITHUB_REPO'? (y/n, or enter different owner/repo): " repo_choice; then
                    if [ "$repo_choice" = "n" ] || [ "$repo_choice" = "no" ]; then
                        GITHUB_REPO=""
                    elif [ ! -z "$repo_choice" ] && [ "$repo_choice" != "y" ] && [ "$repo_choice" != "yes" ]; then
                        GITHUB_REPO="$repo_choice"
                    fi
                fi
            else
                local github_repo
                if read_from_user "Enter GitHub repository (optional, format: owner/repo): " github_repo; then
                    GITHUB_REPO="$github_repo"
                fi
            fi
        fi
    fi
    
    if [ "$GITHUB_AUTH_METHOD" != "none" ]; then
        print_success "GitHub authentication configured!"
        if [ ! -z "$GITHUB_REPO" ]; then
            print_status "Repository: $GITHUB_REPO"
        fi
        if [ ! -z "$GITHUB_TOKEN" ]; then
            print_status "Token: ${GITHUB_TOKEN:0:8}..."
        fi
    fi
    echo ""

    # Call GitLab collection
    collect_gitlab_token
    
    # Call Figma collection
    collect_figma_token
}


# Collect GitLab API token
collect_gitlab_token() {
    print_status "Checking GitLab API configuration..."
    echo ""
    
    # Check if GITLAB_TOKEN is already set in environment
    if [ -n "$GITLAB_TOKEN" ]; then
        print_success "Using GITLAB_TOKEN from environment: ${GITLAB_TOKEN:0:8}..."
        GITLAB_AUTH_METHOD="token"
        
        # Ask if user wants to update token
        if can_interact_with_user; then
            echo ""
            local update_gitlab_token
            if read_from_user "Do you want to update this GitLab token? (y/n): " update_gitlab_token; then
                if [ "$update_gitlab_token" = "y" ] || [ "$update_gitlab_token" = "yes" ]; then
                    GITLAB_TOKEN=""  # Clear the token to prompt for a new one
                    print_status "Please provide the new GitLab token..."
                    
                    # Actually prompt for the new token
                    local new_gitlab_token
                    if read_from_user "Enter your new GitLab Personal Access Token: " new_gitlab_token; then
                        if [ ! -z "$new_gitlab_token" ]; then
                            GITLAB_TOKEN="$new_gitlab_token"
                            print_success "GitLab token updated successfully!"
                        else
                            print_warning "No token provided - keeping original token"
                        fi
                    else
                        print_status "Could not read new token - keeping original"
                    fi
                else
                    print_status "Keeping existing GitLab token"
                fi
            else
                print_status "Could not read input - keeping existing token"
            fi
        else
            print_status "Non-interactive environment - keeping existing GitLab token"
        fi
    fi
    
    # Check if token is configured in Claude config file
    CONFIG_FILE="$HOME/.claude.json"
    if [ -z "$GITLAB_TOKEN" ] && [ -f "$CONFIG_FILE" ]; then
        # Check for existing token in global config
        EXISTING_GITLAB_TOKEN=""
        if command -v jq &> /dev/null; then
            EXISTING_GITLAB_TOKEN=$(jq -r '.mcpServers.gitlab.env.GITLAB_PERSONAL_ACCESS_TOKEN // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
        fi
        
        if [ ! -z "$EXISTING_GITLAB_TOKEN" ] && [ "$EXISTING_GITLAB_TOKEN" != "null" ] && [ "$EXISTING_GITLAB_TOKEN" != "empty" ]; then
            print_success "Found existing GitLab token in Claude config: ${EXISTING_GITLAB_TOKEN:0:8}..."
            GITLAB_TOKEN="$EXISTING_GITLAB_TOKEN"
            GITLAB_AUTH_METHOD="token"
            
            # Ask if user wants to update token
            if can_interact_with_user; then
                echo ""
                local update_existing_gitlab
                if read_from_user "Do you want to update this GitLab token? (y/n): " update_existing_gitlab; then
                    if [ "$update_existing_gitlab" = "y" ] || [ "$update_existing_gitlab" = "yes" ]; then
                        print_status "Please provide the new GitLab token..."
                        
                        # Actually prompt for the new token
                        local new_gitlab_token
                        if read_from_user "Enter your new GitLab Personal Access Token: " new_gitlab_token; then
                            if [ ! -z "$new_gitlab_token" ]; then
                                GITLAB_TOKEN="$new_gitlab_token"
                                print_success "GitLab token updated successfully!"
                            else
                                print_warning "No token provided - keeping existing token"
                            fi
                        else
                            print_status "Could not read new token - keeping existing"
                        fi
                    else
                        print_status "Keeping existing GitLab token"
                    fi
                else
                    print_status "Could not read input - keeping existing token"
                fi
            else
                print_status "Non-interactive environment - keeping existing GitLab token"
            fi
        fi
    fi
    
    # If no token found, ask about configuration
    if [ -z "$GITLAB_TOKEN" ]; then
        if can_interact_with_user; then
            # Ask if user wants to configure GitLab
            echo ""
            print_status "GitLab MCP integration provides access to your GitLab projects, issues, and merge requests."
            
            local configure_gitlab
            if read_from_user "Do you want to configure GitLab integration? (y/n): " configure_gitlab; then
                if [ "$configure_gitlab" = "y" ] || [ "$configure_gitlab" = "yes" ]; then
                    GITLAB_AUTH_METHOD="token"
                    local attempts=0
                    while [ -z "$GITLAB_TOKEN" ] && [ $attempts -lt 3 ]; do
                        echo ""
                        print_status "To create a GitLab Personal Access Token:"
                        echo "1. Go to GitLab.com → Settings → Access Tokens"
                        echo "2. Create a new token with scopes: api, read_user, read_repository"
                        echo "3. Copy the generated token"
                        echo ""
                        
                        local gitlab_token
                        if read_from_user "Enter your GitLab Personal Access Token (or 'skip'): " gitlab_token; then
                            if [ "$gitlab_token" = "skip" ]; then
                                GITLAB_TOKEN=""
                                GITLAB_AUTH_METHOD="none"
                                print_warning "Skipping GitLab MCP integration"
                                break
                            elif [ ! -z "$gitlab_token" ]; then
                                GITLAB_TOKEN="$gitlab_token"
                                print_success "GitLab token configured!"
                                break
                            else
                                print_warning "Token is required for GitLab MCP integration!"
                                attempts=$((attempts + 1))
                            fi
                        else
                            print_status "Could not read input - skipping GitLab integration"
                            GITLAB_AUTH_METHOD="none"
                            break
                        fi
                    done
                else
                    print_status "Skipping GitLab integration"
                    GITLAB_AUTH_METHOD="none"
                fi
            else
                print_status "Could not read input - skipping GitLab integration"
                GITLAB_AUTH_METHOD="none"
            fi
        else
            print_status "Non-interactive environment - skipping GitLab configuration"
            print_status "To enable GitLab integration later, set GITLAB_TOKEN environment variable"
            GITLAB_AUTH_METHOD="none"
        fi
    fi
    
    # Get GitLab API URL (optional, defaults to gitlab.com)
    if [ ! -z "$GITLAB_TOKEN" ]; then
        GITLAB_API_URL=${GITLAB_API_URL:-"https://gitlab.com/api/v4"}
        
        if can_interact_with_user; then
            echo ""
            local custom_gitlab_url
            if read_from_user "GitLab API URL [default: https://gitlab.com/api/v4]: " custom_gitlab_url; then
                if [ ! -z "$custom_gitlab_url" ]; then
                    GITLAB_API_URL="$custom_gitlab_url"
                fi
            fi
        fi
        
        print_success "GitLab authentication configured!"
        print_status "API URL: $GITLAB_API_URL"
        print_status "Token: ${GITLAB_TOKEN:0:8}..."
    fi
    echo ""
    
    return 0
}


# Collect Figma API token
collect_figma_token() {
    print_status "Checking Figma API configuration..."
    echo ""
    
    # Check if FIGMA_ACCESS_TOKEN is already set in environment
    if [ -n "$FIGMA_ACCESS_TOKEN" ]; then
        print_success "Using FIGMA_ACCESS_TOKEN from environment: ${FIGMA_ACCESS_TOKEN:0:8}..."
        
        # Ask if user wants to update token
        if can_interact_with_user; then
            echo ""
            local update_figma_token
            if read_from_user "Do you want to update this Figma token? (y/n): " update_figma_token; then
                if [ "$update_figma_token" = "y" ] || [ "$update_figma_token" = "yes" ]; then
                    print_status "Please provide the new Figma access token..."
                    
                    # Actually prompt for the new token
                    local new_figma_token
                    if read_from_user "Enter your new Figma Personal Access Token: " new_figma_token; then
                        if [ ! -z "$new_figma_token" ]; then
                            FIGMA_ACCESS_TOKEN="$new_figma_token"
                            print_success "Figma token updated successfully!"
                        else
                            print_warning "No token provided - keeping existing token"
                        fi
                    else
                        print_status "Could not read new token - keeping existing"
                    fi
                else
                    print_status "Keeping existing Figma token"
                fi
                return 0
            else
                print_status "Could not read input - keeping existing token"
                return 0
            fi
        else
            print_status "Non-interactive environment - keeping existing Figma token"
            return 0
        fi
    fi
    
    # Check Claude config for existing token
    CONFIG_FILE="$HOME/.claude.json"
    if [ -z "$FIGMA_ACCESS_TOKEN" ] && [ -f "$CONFIG_FILE" ]; then
        EXISTING_FIGMA_TOKEN=""
        if command -v jq &> /dev/null; then
            EXISTING_FIGMA_TOKEN=$(jq -r '
                (.mcpServers."figma".args[] | select(startswith("--figma-api-key=")) | sub("--figma-api-key="; "")) // 
                empty
            ' "$CONFIG_FILE" 2>/dev/null || echo "")
        fi
        
        if [ ! -z "$EXISTING_FIGMA_TOKEN" ] && [ "$EXISTING_FIGMA_TOKEN" != "null" ] && [ "$EXISTING_FIGMA_TOKEN" != "empty" ]; then
            print_success "Found existing Figma token in Claude config: ${EXISTING_FIGMA_TOKEN:0:8}..."
            FIGMA_ACCESS_TOKEN="$EXISTING_FIGMA_TOKEN"
            
            # Ask if user wants to update token
            if can_interact_with_user; then
                echo ""
                local update_existing_figma
                if read_from_user "Do you want to update this Figma token? (y/n): " update_existing_figma; then
                    if [ "$update_existing_figma" = "y" ] || [ "$update_existing_figma" = "yes" ]; then
                        print_status "Please provide the new Figma access token..."
                        
                        # Actually prompt for the new token
                        local new_figma_token
                        if read_from_user "Enter your new Figma Personal Access Token: " new_figma_token; then
                            if [ ! -z "$new_figma_token" ]; then
                                FIGMA_ACCESS_TOKEN="$new_figma_token"
                                print_success "Figma token updated successfully!"
                            else
                                print_warning "No token provided - keeping existing token"
                            fi
                        else
                            print_status "Could not read new token - keeping existing"
                        fi
                    else
                        print_status "Keeping existing Figma token"
                    fi
                    return 0
                else
                    print_status "Could not read input - keeping existing token"
                    return 0
                fi
            else
                print_status "Non-interactive environment - keeping existing Figma token"
                return 0
            fi
        fi
    fi
    
    # If no token found, ask about configuration
    if [ -z "$FIGMA_ACCESS_TOKEN" ]; then
        if can_interact_with_user; then
            # Ask if user wants to configure Figma
            echo ""
            print_status "Figma MCP integration provides access to your Figma designs and components."
            
            local configure_figma
            if read_from_user "Do you want to configure Figma integration? (y/n): " configure_figma; then
                if [ "$configure_figma" = "y" ] || [ "$configure_figma" = "yes" ]; then
                    echo ""
                    print_status "To create a Figma Personal Access Token:"
                    echo "1. Go to Figma.com → Settings → Account → Personal access tokens"
                    echo "2. Click 'Create new token'"
                    echo "3. Give it a descriptive name (e.g., 'Claude Code MCP')"
                    echo "4. Copy the generated token"
                    echo ""
                    
                    local figma_token
                    if read_from_user "Enter your Figma Personal Access Token (or 'skip'): " figma_token; then
                        if [ "$figma_token" = "skip" ] || [ -z "$figma_token" ]; then
                            FIGMA_ACCESS_TOKEN=""
                            print_status "Skipping Figma integration"
                        else
                            FIGMA_ACCESS_TOKEN="$figma_token"
                            print_success "Figma token configured!"
                        fi
                    else
                        print_status "Could not read input - skipping Figma integration"
                        FIGMA_ACCESS_TOKEN=""
                    fi
                else
                    print_status "Skipping Figma integration"
                    FIGMA_ACCESS_TOKEN=""
                fi
            else
                print_status "Could not read input - skipping Figma integration"
                FIGMA_ACCESS_TOKEN=""
            fi
        else
            print_status "Non-interactive environment - skipping Figma configuration"
            print_status "To enable Figma integration later, set FIGMA_ACCESS_TOKEN environment variable"
            FIGMA_ACCESS_TOKEN=""
        fi
    fi
    
    if [ ! -z "$FIGMA_ACCESS_TOKEN" ]; then
        print_success "Figma authentication configured!"
        print_status "Token: ${FIGMA_ACCESS_TOKEN:0:8}..."
    fi
    echo ""
    
    return 0
}

# Install Figma MCP Server
install_figma() {
    if [ -z "$FIGMA_ACCESS_TOKEN" ]; then
        print_status "Skipping Figma MCP server installation (no token provided)"
        return 0
    fi
    
    print_status "Configuring Figma MCP Server..."
    
    # The Figma MCP is installed via npx, so no local installation needed
    # Just verify npx is available
    if ! command -v npx &> /dev/null; then
        print_warning "npx is required for Figma MCP but not found!"
        print_status "Figma MCP will be skipped. Install Node.js to enable Figma integration."
        return 0
    fi
    
    print_success "Figma MCP Server ready for configuration!"
    return 0
}

# Configure GitLab MCP server
configure_gitlab_mcp() {
    if [ -z "$GITLAB_TOKEN" ] || [ "$GITLAB_AUTH_METHOD" = "none" ]; then
        print_status "Skipping GitLab MCP configuration (no token provided)"
        return 0
    fi
    
    print_status "Configuring GitLab MCP server..."
    
    # Configure GitLab MCP server (global)
    if ! claude mcp list 2>/dev/null | grep -q "^gitlab:"; then
        print_status "Adding global GitLab MCP server..."
        
        # Build the command with environment variables
        local gitlab_cmd="claude mcp add gitlab npx @zereight/mcp-gitlab"
        
        # Set environment variables for the command
        export GITLAB_PERSONAL_ACCESS_TOKEN="$GITLAB_TOKEN"
        export GITLAB_API_URL="$GITLAB_API_URL"
        
        if $gitlab_cmd; then
            print_success "Global GitLab MCP server added"
        else
            print_warning "Failed to add GitLab MCP server via CLI, trying config file method..."
            
            # Fallback: update config file directly
            if update_gitlab_token_in_config "$GITLAB_TOKEN" "$GITLAB_API_URL"; then
                print_success "GitLab MCP server configured via config file"
            else
                print_warning "⚠️  Could not configure GitLab MCP automatically"
                print_status "You can configure it manually later by running:"
                echo "  export GITLAB_PERSONAL_ACCESS_TOKEN=\"$GITLAB_TOKEN\""
                echo "  export GITLAB_API_URL=\"$GITLAB_API_URL\""
                echo "  claude mcp add gitlab npx @zereight/mcp-gitlab"
                return 0  # Don't fail the entire installation
            fi
        fi
    else
        print_success "Global GitLab MCP server already configured"
        
        # Update token if provided
        CONFIG_FILE="$HOME/.claude.json"
        if [ -f "$CONFIG_FILE" ]; then
            # Check if token needs updating
            CURRENT_GITLAB_TOKEN=""
            if command -v jq &> /dev/null; then
                CURRENT_GITLAB_TOKEN=$(jq -r '.mcpServers.gitlab.env.GITLAB_PERSONAL_ACCESS_TOKEN // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
            fi
            
            if [ "$CURRENT_GITLAB_TOKEN" != "$GITLAB_TOKEN" ]; then
                print_status "Updating GitLab token in existing configuration..."
                if update_gitlab_token_in_config "$GITLAB_TOKEN" "$GITLAB_API_URL"; then
                    print_success "GitLab token updated successfully!"
                else
                    print_warning "Please manually update your GitLab token in ~/.claude.json"
                fi
            else
                print_status "GitLab token already up to date"
            fi
        fi
    fi
    
    return 0
}

# Helper function to update GitLab token in config
update_gitlab_token_in_config() {
    local CONFIG_FILE="$HOME/.claude.json"
    local TOKEN="$1"
    local API_URL="$2"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_warning "Claude config file not found at $CONFIG_FILE"
        return 1
    fi
    
    # Create a backup
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup"
    
    # Try jq first (cleanest method)
    if command -v jq &> /dev/null; then
        # Update GitLab MCP server config
        if jq --arg token "$TOKEN" --arg apiUrl "$API_URL" \
           '# Update or create GitLab MCP server config
            .mcpServers."gitlab" = {
              "command": "npx",
              "args": ["@zereight/mcp-gitlab"],
              "env": {
                "GITLAB_PERSONAL_ACCESS_TOKEN": $token,
                "GITLAB_API_URL": $apiUrl
              }
            }' \
           "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"; then
            print_success "GitLab token configured using jq!"
            return 0
        fi
    fi
    
    # Try Python (more reliable than sed)
    if command -v python3 &> /dev/null; then
        cat > /tmp/update_gitlab_token.py << PYTHON_EOF
#!/usr/bin/env python3
import json
import sys

try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    
    # Ensure mcpServers exists
    if 'mcpServers' not in config:
        config['mcpServers'] = {}
    
    # Add or update GitLab MCP server
    config['mcpServers']['gitlab'] = {
        "command": "npx",
        "args": ["@zereight/mcp-gitlab"],
        "env": {
            "GITLAB_PERSONAL_ACCESS_TOKEN": "$TOKEN",
            "GITLAB_API_URL": "$API_URL"
        }
    }
    
    with open('$CONFIG_FILE', 'w') as f:
        json.dump(config, f, indent=2)
    print("SUCCESS")
except Exception as e:
    print(f"ERROR: {e}")
PYTHON_EOF
        
        RESULT=$(python3 /tmp/update_gitlab_token.py 2>&1)
        rm -f /tmp/update_gitlab_token.py
        
        if [ "$RESULT" = "SUCCESS" ]; then
            print_success "GitLab token configured using Python!"
            return 0
        fi
    fi
    
    print_warning "Could not automatically configure GitLab token"
    return 1
}

# Helper function to update Figma token in config
update_figma_token_in_config() {
    local CONFIG_FILE="$HOME/.claude.json"
    local TOKEN="$1"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_warning "Claude config file not found at $CONFIG_FILE"
        return 1
    fi
    
    # Create a backup
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup"
    
    # Try jq first (cleanest method) - FIXED: removed -y flag
    if command -v jq &> /dev/null; then
        # Update Figma MCP server config
        if jq --arg token "$TOKEN" \
           '# Update or create Figma MCP server config
            .mcpServers."figma" = {
              "command": "npx",
              "args": ["figma-developer-mcp", ("--figma-api-key=" + $token), "--stdio"]
            }' \
           "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"; then
            print_success "Figma token configured using jq!"
            return 0
        fi
    fi
    
    # Try Python (more reliable than sed) - FIXED: removed -y flag
    if command -v python3 &> /dev/null; then
        cat > /tmp/update_figma_token.py << PYTHON_EOF
#!/usr/bin/env python3
import json
import sys

try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    
    # Ensure mcpServers exists
    if 'mcpServers' not in config:
        config['mcpServers'] = {}
    
    # Add or update Figma MCP server (without -y flag)
    config['mcpServers']['figma'] = {
        "command": "npx",
        "args": ["figma-developer-mcp", "--figma-api-key=$TOKEN", "--stdio"]
    }
    
    with open('$CONFIG_FILE', 'w') as f:
        json.dump(config, f, indent=2)
    print("SUCCESS")
except Exception as e:
    print(f"ERROR: {e}")
PYTHON_EOF
        
        RESULT=$(python3 /tmp/update_figma_token.py 2>&1)
        rm -f /tmp/update_figma_token.py
        
        if [ "$RESULT" = "SUCCESS" ]; then
            print_success "Figma token configured using Python!"
            return 0
        fi
    fi
    
    print_warning "Could not automatically configure Figma token"
    return 1
}

# Updated configure_claude_mcp function (add this after the existing global servers)
configure_figma_mcp() {
    if [ -z "$FIGMA_ACCESS_TOKEN" ]; then
        print_status "Skipping Figma MCP configuration (no token provided)"
        return 0
    fi
    
    print_status "Configuring Figma MCP server..."
    
    # Configure Figma MCP server (global) - FIXED command without -y flag
    if ! claude mcp list 2>/dev/null | grep -q "^figma:"; then
        print_status "Adding global Figma MCP server..."
        # Remove the -y flag that was causing the error
        if claude mcp add "figma" npx figma-developer-mcp --figma-api-key="$FIGMA_ACCESS_TOKEN" --stdio; then
            print_success "Global Figma MCP server added"
        else
            print_warning "Failed to add Figma MCP server via CLI, trying config file method..."
            
            # Fallback: update config file directly
            if update_figma_token_in_config "$FIGMA_ACCESS_TOKEN"; then
                print_success "Figma MCP server configured via config file"
            else
                print_warning "⚠️  Could not configure Figma MCP automatically"
                print_status "You can configure it manually later by running:"
                echo "  claude mcp add figma npx figma-developer-mcp --figma-api-key=YOUR_TOKEN --stdio"
                return 0  # Don't fail the entire installation
            fi
        fi
    else
        print_success "Global Figma MCP server already configured"
        
        # Update token if provided
        CONFIG_FILE="$HOME/.claude.json"
        if [ -f "$CONFIG_FILE" ]; then
            # Check if token needs updating
            CURRENT_TOKEN=""
            if command -v jq &> /dev/null; then
                CURRENT_TOKEN=$(jq -r '.mcpServers.figma.args[] | select(startswith("--figma-api-key=")) | sub("--figma-api-key="; "")' "$CONFIG_FILE" 2>/dev/null)
            fi
            
            if [ "$CURRENT_TOKEN" != "$FIGMA_ACCESS_TOKEN" ]; then
                print_status "Updating Figma token in existing configuration..."
                if update_figma_token_in_config "$FIGMA_ACCESS_TOKEN"; then
                    print_success "Figma token updated successfully!"
                else
                    print_warning "Please manually update your Figma token in ~/.claude.json"
                fi
            else
                print_status "Figma token already up to date"
            fi
        fi
    fi
    
    return 0
}

# Check if Claude Code is installed
check_claude_code() {
    if ! command -v claude &> /dev/null; then
        print_error "Claude Code is not installed!"
        print_error "Please install Claude Code first: https://claude.ai/code"
        exit 1
    fi
    print_success "Claude Code is installed!"
}

# Check if Node.js and npm are installed
check_node() {
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed! Please install Node.js first."
        exit 1
    fi
    
    if ! command -v npm &> /dev/null; then
        print_error "npm is not installed! Please install npm first."
        exit 1
    fi
    
    print_success "Node.js and npm are available!"
}

# Create MCP servers directory
create_mcp_directory() {
    print_status "Creating MCP servers directory..."
    
    MCP_DIR="$HOME/.config/claude-code/mcp-servers"
    mkdir -p "$MCP_DIR"
    
    print_success "MCP directory created at: $MCP_DIR"
}

# Install Context7 MCP Server
install_context7() {
    print_status "Installing Context7 MCP Server..."
    
    cd "$MCP_DIR"
    
    # Clean install if directory exists
    if [ -d "context7" ]; then
        print_status "Removing existing context7 installation..."
        rm -rf context7
    fi
    
    print_status "Cloning Context7 repository..."
    if ! git clone https://github.com/upstash/context7.git context7; then
        print_error "Failed to clone Context7 repository"
        return 1
    fi
    
    cd context7
    
    print_status "Installing Context7 dependencies..."
    if ! npm install; then
        print_error "Failed to install Context7 dependencies"
        return 1
    fi
    
    print_status "Building Context7..."
    if ! npm run build; then
        print_error "Failed to build Context7"
        return 1
    fi
    
    # Verify the build was successful (Context7 builds to dist/index.js, not build/index.js)
    if [ -f "dist/index.js" ]; then
        print_success "Context7 MCP Server installed and built successfully!"
    else
        print_error "Context7 build failed - dist/index.js not found"
        return 1
    fi
}

# Install Filesystem MCP Server
install_filesystem() {
    print_status "Installing Filesystem MCP Server..."
    
    npm install -g @modelcontextprotocol/server-filesystem
    
    print_success "Filesystem MCP Server installed!"
}

# Install Database MCP Server
install_database() {
    print_status "Installing Database MCP Server (Go-based)..."
    
    # Check Go version requirement (1.22+)
    if ! command -v go &> /dev/null; then
        print_warning "Go is not installed. Installing via Homebrew..."
        if command -v brew &> /dev/null; then
            brew install go
        else
            print_error "Go is required but not installed. Please install Go first."
            print_status "Install with: brew install go (macOS) or visit https://golang.org/dl/"
            return 1
        fi
    fi
    
    # Check Go version (must be 1.22+)
    GO_VERSION=$(go version | grep -o 'go[0-9]*\.[0-9]*' | grep -o '[0-9]*\.[0-9]*')
    REQUIRED_VERSION="1.22"
    if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$GO_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
        print_error "Go version $GO_VERSION is installed, but version $REQUIRED_VERSION or higher is required."
        print_status "Please update Go: brew upgrade go (macOS) or download from https://golang.org/dl/"
        return 1
    fi
    
    print_success "Go version $GO_VERSION meets requirements!"
    
    cd "$MCP_DIR"
    
    # Clean install if directory exists
    if [ -d "db-mcp-server" ]; then
        print_status "Removing existing db-mcp-server installation..."
        rm -rf db-mcp-server
    fi
    
    print_status "Cloning db-mcp-server repository..."
    if ! git clone https://github.com/FreePeak/db-mcp-server.git db-mcp-server; then
        print_error "Failed to clone db-mcp-server repository"
        return 1
    fi
    
    cd db-mcp-server
    
    # Build the Go project with better error handling
    print_status "Building Go database MCP server..."
    
    # Try different build methods
    if [ -f "Makefile" ]; then
        print_status "Using Makefile to build..."
        if make build; then
            print_success "Database MCP server built successfully using Makefile!"
        else
            print_warning "Makefile build failed, trying direct Go build..."
            if go build -o bin/server ./cmd/server; then
                print_success "Database MCP server built successfully using Go build!"
            else
                print_error "Go build failed. Database MCP server installation failed."
                return 1
            fi
        fi
    else
        print_status "No Makefile found, using direct Go build..."
        # Ensure bin directory exists
        mkdir -p bin
        if go build -o bin/server ./cmd/server; then
            print_success "Database MCP server built successfully!"
        elif go build -o bin/server .; then
            print_success "Database MCP server built successfully (fallback method)!"
        else
            print_error "Go build failed. Database MCP server installation failed."
            print_status "This is optional - other MCP servers will still work."
            return 1
        fi
    fi
    
    # Verify the binary was created
    if [ -f "bin/server" ] || [ -f "db-mcp-server" ]; then
        print_success "Database MCP Server installed!"
    else
        print_error "Database binary not found after build"
        return 1
    fi
}

# Install Web Fetch MCP Server
install_web_fetch() {
    print_status "Installing Web Fetch MCP Server..."
    
    cd "$MCP_DIR"
    
    if [ ! -d "fetch-mcp" ]; then
        git clone https://github.com/zcaceres/fetch-mcp.git fetch-mcp
    fi
    
    cd fetch-mcp
    
    # Install dependencies and build
    npm install
    npm run build
    
    print_success "Web Fetch MCP Server installed!"
}

# Install GitHub MCP Server
install_github() {
    print_status "Installing GitHub MCP Server..."
    
    npm install -g @modelcontextprotocol/server-github
    
    print_success "GitHub MCP Server installed!"
}

# Install GitLab MCP Server
install_gitlab() {
    print_status "Installing GitLab MCP Server..."
    
    npm install -g @zereight/mcp-gitlab
    
    print_success "GitLab MCP Server installed!"
}

# Install Memory MCP Server
install_memory() {
    print_status "Installing Memory MCP Server..."
    
    npm install -g @modelcontextprotocol/server-memory
    
    print_success "Memory MCP Server installed!"
}

# Install Laravel DebugBar MCP Server (optional, requires DebugBar package)
install_debugbar_mcp() {
    print_status "Installing Laravel DebugBar MCP Server (optional)..."
    
    # Check if Laravel DebugBar is installed
    if grep -q "barryvdh/laravel-debugbar" composer.json 2>/dev/null; then
        print_status "Laravel DebugBar detected, installing MCP server..."
        
        cd "$MCP_DIR"
        
        # Clone the correct repository
        if [ ! -d "laravel-debugbar-mcp" ]; then
            if git clone https://github.com/021-factory/laravel-debugbar-mcp.git laravel-debugbar-mcp; then
                cd laravel-debugbar-mcp
                npm install
                npm run build
                print_success "Laravel DebugBar MCP Server installed!"
            else
                print_error "Failed to clone Laravel DebugBar MCP repository"
                return 1
            fi
        else
            print_status "Laravel DebugBar MCP already cloned, updating..."
            cd laravel-debugbar-mcp
            git pull
            npm install
            npm run build
            print_success "Laravel DebugBar MCP Server updated!"
        fi
    else
        print_warning "Laravel DebugBar not found. Skipping DebugBar MCP installation."
        print_status "To use DebugBar MCP later, install: composer require barryvdh/laravel-debugbar --dev"
    fi
}

# Parse Laravel .env file
parse_env() {
    print_status "Parsing Laravel .env file..."
    
    # Source the .env file
    if [ -f ".env" ]; then
        export $(grep -v '^#' .env | xargs)
    fi
    
    # Get database connection details
    DB_CONNECTION=${DB_CONNECTION:-mysql}
    DB_HOST=${DB_HOST:-127.0.0.1}
    DB_PORT=${DB_PORT:-3306}
    DB_DATABASE=${DB_DATABASE:-}
    DB_USERNAME=${DB_USERNAME:-}
    DB_PASSWORD=${DB_PASSWORD:-}
    
    print_success "Environment variables parsed!"
}

# Generate database configuration
generate_database_config() {
    print_status "Generating database configuration..."
    
    PROJECT_PATH="$PWD"
    
    # Generate database configuration if database is configured
    if [ ! -z "$DB_DATABASE" ]; then
        # Determine the correct database type
        case "$DB_CONNECTION" in
            "mysql")
                DB_TYPE="mysql"
                ;;
            "pgsql"|"postgres"|"postgresql")
                DB_TYPE="postgres"
                ;;
            "sqlite")
                DB_TYPE="sqlite"
                if [[ "$DB_DATABASE" == /* ]]; then
                    DB_PATH="$DB_DATABASE"
                else
                    DB_PATH="$PROJECT_PATH/database/$DB_DATABASE"
                fi
                ;;
            *)
                DB_TYPE="mysql"
                ;;
        esac
        
        # Create the database configuration file
        if [ "$DB_CONNECTION" = "sqlite" ]; then
            cat > "$MCP_DIR/db-mcp-server/config.json" << 'DBEOF'
{
  "connections": [
    {
      "id": "laravel",
      "type": "sqlite",
      "database": "$DB_PATH",
      "query_timeout": 60,
      "max_open_conns": 10,
      "max_idle_conns": 2,
      "conn_max_lifetime_seconds": 300,
      "conn_max_idle_time_seconds": 60
    }
  ]
}
DBEOF
        else
            cat > "$MCP_DIR/db-mcp-server/config.json" << DBEOF
{
  "connections": [
    {
      "id": "laravel",
      "type": "$DB_TYPE",
      "host": "$DB_HOST",
      "port": $DB_PORT,
      "name": "$DB_DATABASE",
      "user": "$DB_USERNAME",
      "password": "$DB_PASSWORD",
      "query_timeout": 60,
      "max_open_conns": 20,
      "max_idle_conns": 5,
      "conn_max_lifetime_seconds": 300,
      "conn_max_idle_time_seconds": 60
    }
  ]
}
DBEOF
        fi
        print_status "Database configuration created!"
    else
        print_warning "No database configured in .env file. Database MCP server will be skipped."
        print_status "To enable database MCP later, configure your database in .env and re-run the script."
    fi
    
    print_success "Database configuration completed!"
}

# Helper function to update GitHub token in config
update_github_token_in_config() {
    local CONFIG_FILE="$HOME/.claude.json"
    local TOKEN="$1"
    local PROJECT_PATH="$2"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_warning "Claude config file not found at $CONFIG_FILE"
        return 1
    fi
    
    # Create a backup
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup"
    
    # Try jq first (cleanest method)
    if command -v jq &> /dev/null; then
        # Update both global and project-specific GitHub server configs
        if jq --arg token "$TOKEN" --arg project "$PROJECT_PATH" \
           '# Update global config if it exists
            if .mcpServers.github then
              .mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN = $token
            else . end |
            # Update project-specific config
            if .projects[$project].mcpServers.github then
              .projects[$project].mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN = $token
            else . end' \
           "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"; then
            print_success "GitHub token configured using jq!"
            return 0
        fi
    fi
    
    # Try Python (more reliable than sed)
    if command -v python3 &> /dev/null; then
        cat > /tmp/update_github_token.py << PYTHON_EOF
#!/usr/bin/env python3
import json
import sys

try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    
    # Update global config if it exists
    if 'mcpServers' in config:
        if 'github' not in config['mcpServers']:
            config['mcpServers']['github'] = {}
        if 'env' not in config['mcpServers']['github']:
            config['mcpServers']['github']['env'] = {}
        config['mcpServers']['github']['env']['GITHUB_PERSONAL_ACCESS_TOKEN'] = '$TOKEN'
    
    # Update project-specific config
    if 'projects' in config and '$PROJECT_PATH' in config['projects']:
        project = config['projects']['$PROJECT_PATH']
        if 'mcpServers' in project and 'github' in project['mcpServers']:
            if 'env' not in project['mcpServers']['github']:
                project['mcpServers']['github']['env'] = {}
            project['mcpServers']['github']['env']['GITHUB_PERSONAL_ACCESS_TOKEN'] = '$TOKEN'
    
    with open('$CONFIG_FILE', 'w') as f:
        json.dump(config, f, indent=2)
    print("SUCCESS")
except Exception as e:
    print(f"ERROR: {e}")
PYTHON_EOF
        
        RESULT=$(python3 /tmp/update_github_token.py 2>&1)
        rm -f /tmp/update_github_token.py
        
        if [ "$RESULT" = "SUCCESS" ]; then
            print_success "GitHub token configured using Python!"
            return 0
        fi
    fi
    
    print_warning "Could not automatically configure GitHub token"
    return 1
}

# Configure Claude Code MCP Servers
configure_claude_mcp() {
    print_status "Configuring Claude Code MCP servers..."
    
    PROJECT_PATH="$PWD"
    PROJECT_NAME=$(basename "$PROJECT_PATH")
    
    # Create a project identifier for unique MCP server names
    PROJECT_ID=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID="laravel$(date +%s)"
    fi
    
    print_status "Project: $PROJECT_NAME (ID: $PROJECT_ID)"
    
    # Check if claude command is available
    if ! command -v claude &> /dev/null; then
        print_error "Claude Code CLI not found. Please ensure Claude Code is properly installed."
        return 1
    fi
    
    print_status "Setting up global MCP servers (if not already configured)..."
    
    # Setup GLOBAL MCP servers (shared across all projects)
    
    # Configure GitHub MCP server
    if ! claude mcp list 2>/dev/null | grep -q "^github:"; then
        print_status "Adding global GitHub MCP server..."
        if [ "$GITHUB_AUTH_METHOD" != "none" ]; then
            if claude mcp add "github" npx @modelcontextprotocol/server-github; then
                print_success "Global GitHub MCP server added"
                
                # Configure token if available
                if [ "$GITHUB_AUTH_METHOD" = "token" ] && [ ! -z "$GITHUB_TOKEN" ]; then
                    print_status "Configuring GitHub token..."
                    # Pass the project path to the update function
                    if update_github_token_in_config "$GITHUB_TOKEN" "$PROJECT_PATH"; then
                        print_success "GitHub token configured successfully!"
                    else
                        print_warning "⚠️  Manual configuration required for GitHub private repo access"
                        echo ""
                        echo "Please edit ~/.claude.json and add your token to BOTH:"
                        echo ""
                        echo "1. Global config (at the bottom of file):"
                        echo '  "mcpServers": {'
                        echo '    "github": {'
                        echo '      "env": {'
                        echo '        "GITHUB_PERSONAL_ACCESS_TOKEN": "'$GITHUB_TOKEN'"'
                        echo '      }'
                        echo '    }'
                        echo '  }'
                        echo ""
                        echo "2. Project-specific config (in projects.'$PROJECT_PATH'.mcpServers):"
                        echo '  "github": {'
                        echo '    "type": "stdio",'
                        echo '    "command": "npx",'
                        echo '    "args": ["@modelcontextprotocol/server-github"],'
                        echo '    "env": {'
                        echo '      "GITHUB_PERSONAL_ACCESS_TOKEN": "'$GITHUB_TOKEN'"'
                        echo '    }'
                        echo '  }'
                        echo ""
                    fi
                fi
            else
                print_error "Failed to add GitHub MCP server"
            fi
        fi
    else
        print_success "Global GitHub MCP server already configured"
        
        # Update token if provided and not already configured
        if [ "$GITHUB_AUTH_METHOD" = "token" ] && [ ! -z "$GITHUB_TOKEN" ]; then
            CONFIG_FILE="$HOME/.claude.json"
            if [ -f "$CONFIG_FILE" ]; then
                # Check if token is configured in the project-specific config
                PROJECT_HAS_TOKEN=$(jq -r --arg project "$PROJECT_PATH" \
                    '.projects[$project].mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN // "not_found"' \
                    "$CONFIG_FILE" 2>/dev/null)
                
                if [ "$PROJECT_HAS_TOKEN" = "not_found" ] || [ -z "$PROJECT_HAS_TOKEN" ]; then
                    print_warning "GitHub server exists but token not configured in project"
                    print_status "Configuring GitHub token..."
                    if update_github_token_in_config "$GITHUB_TOKEN" "$PROJECT_PATH"; then
                        print_success "GitHub token configured successfully!"
                    else
                        print_warning "Please manually add your GitHub token to ~/.claude.json"
                    fi
                else
                    print_status "GitHub token already configured in project"
                fi
            fi
        fi
    fi

    # Add GitLab configuration after other global servers
    configure_gitlab_mcp

    # Add Figma configuration after other global servers
    configure_figma_mcp

    
    # Add global Memory MCP server
    if ! claude mcp list 2>/dev/null | grep -q "^memory:"; then
        print_status "Adding global Memory MCP server..."
        if claude mcp add "memory" npx @modelcontextprotocol/server-memory; then
            print_success "Global Memory MCP server added"
        else
            print_warning "Failed to add global Memory MCP server"
        fi
    else
        print_success "Global Memory MCP server already configured"
    fi
    
    # Add global Context7 MCP server
    if [ -f "$MCP_DIR/context7/dist/index.js" ]; then
        if ! claude mcp list 2>/dev/null | grep -q "^context7:"; then
            print_status "Adding global Context7 MCP server..."
            if claude mcp add "context7" node "$MCP_DIR/context7/dist/index.js"; then
                print_success "Global Context7 MCP server added"
            else
                print_warning "Failed to add global Context7 MCP server"
            fi
        else
            print_success "Global Context7 MCP server already configured"
        fi
    fi
    
    # Add global Web Fetch MCP server
    if [ -f "$MCP_DIR/fetch-mcp/dist/index.js" ]; then
        if ! claude mcp list 2>/dev/null | grep -q "^webfetch:"; then
            print_status "Adding global Web Fetch MCP server..."
            if claude mcp add "webfetch" node "$MCP_DIR/fetch-mcp/dist/index.js"; then
                print_success "Global Web Fetch MCP server added"
            else
                print_warning "Failed to add global Web Fetch MCP server"
            fi
        else
            print_success "Global Web Fetch MCP server already configured"
        fi
    fi
    
    print_status "Setting up project-specific MCP servers..."
    
    # Clean up old project-specific servers
    print_status "Cleaning up existing project-specific MCP servers..."
    claude mcp list 2>/dev/null | grep -E "^(filesystem|database|debugbar)-$PROJECT_ID" | awk '{print $1}' | xargs -I {} claude mcp remove {} 2>/dev/null || true
    
    # Add PROJECT-SPECIFIC MCP servers (only filesystem and database)
    
    # Add Filesystem MCP server (project-specific)
    print_status "Adding Filesystem MCP server for $PROJECT_NAME..."
    if claude mcp add "filesystem-$PROJECT_ID" npx @modelcontextprotocol/server-filesystem "$PROJECT_PATH"; then
        print_success "Filesystem MCP server added: filesystem-$PROJECT_ID"
    else
        print_warning "Failed to add Filesystem MCP server"
    fi
    
    # Add Database MCP server (project-specific)
    if [ -f "$MCP_DIR/db-mcp-server/config.json" ] && [ ! -z "$DB_DATABASE" ]; then
        # Create project-specific database config
        PROJECT_DB_CONFIG="$MCP_DIR/db-mcp-server/config-$PROJECT_ID.json"
        cp "$MCP_DIR/db-mcp-server/config.json" "$PROJECT_DB_CONFIG"
        
        # Find database binary
        DB_BINARY=""
        if [ -f "$MCP_DIR/db-mcp-server/bin/server" ]; then
            DB_BINARY="$MCP_DIR/db-mcp-server/bin/server"
        elif [ -f "$MCP_DIR/db-mcp-server/db-mcp-server" ]; then
            DB_BINARY="$MCP_DIR/db-mcp-server/db-mcp-server"
        fi
        
        if [ ! -z "$DB_BINARY" ] && [ -x "$DB_BINARY" ]; then
            print_status "Adding Database MCP server for $PROJECT_NAME..."
            if claude mcp add "database-$PROJECT_ID" "$DB_BINARY" -- -t stdio -c "$PROJECT_DB_CONFIG"; then
                print_success "Database MCP server added: database-$PROJECT_ID"
            else
                print_warning "Failed to add Database MCP server"
            fi
        else
            print_warning "Database binary not found or not executable"
        fi
    else
        if [ -z "$DB_DATABASE" ]; then
            print_status "No database configured in .env file, skipping Database MCP server"
        fi
    fi
    
    # Add Laravel DebugBar MCP if available
    if grep -q "barryvdh/laravel-debugbar" composer.json 2>/dev/null; then
        print_status "Adding Laravel DebugBar MCP server for $PROJECT_NAME..."
        if [ -f "$MCP_DIR/laravel-debugbar-mcp/build/index.js" ]; then
            if LARAVEL_PROJECT_PATH="$PROJECT_PATH" claude mcp add "debugbar-$PROJECT_ID" node "$MCP_DIR/laravel-debugbar-mcp/build/index.js"; then
                print_success "Laravel DebugBar MCP server added: debugbar-$PROJECT_ID"
            else
                print_warning "Failed to add Laravel DebugBar MCP server"
            fi
        else
            print_warning "Laravel DebugBar MCP server not built properly - skipping"
        fi
    fi
    
    # Display final configuration
    print_status "Final MCP server configuration:"
    claude mcp list
    
    print_success "Claude Code MCP configuration completed!"
    
    # Show summary
    echo ""
    print_status "MCP Server Configuration Summary:"
    echo ""
    print_status "Global MCP servers (shared across all projects):"
    claude mcp list | grep -E "^(github|gitlab|memory|context7|webfetch|figma):" | sed 's/^/  ✅ /' || true
    echo ""
    print_status "Project-specific MCP servers for $PROJECT_NAME:"
    claude mcp list | grep -E "^(filesystem|database|debugbar)-$PROJECT_ID" | sed 's/^/  ✅ /' || true
    echo ""
    
    print_status "💡 Usage Tips:"
    echo "  • Global servers work across all your projects"
    echo "  • Filesystem access is specific to: $PROJECT_PATH"
    if [ ! -z "$DB_DATABASE" ]; then
        echo "  • Database access is configured for: $DB_DATABASE"
    fi
    echo "  • Memory is shared - decisions in one project can inform others"
    echo "  • GitHub can access any repository you have permissions for"
}

# Create project-specific Claude prompts
create_project_prompts() {
    print_status "Creating project-specific Claude prompts..."
    
    # Get current project details
    PROJECT_NAME=$(basename "$PWD")
    PROJECT_PATH="$PWD"
    
    # Ensure we're in the correct directory
    cd "$PROJECT_PATH"
    
    # Create .claude directory with explicit error checking
    if ! mkdir -p ".claude"; then
        print_error "Failed to create .claude directory in $PROJECT_PATH"
        return 1
    fi
    
    if ! mkdir -p ".claude/memory"; then
        print_error "Failed to create .claude/memory directory in $PROJECT_PATH"
        return 1
    fi
    
    # Verify directories were created
    if [ ! -d ".claude" ]; then
        print_error ".claude directory was not created successfully"
        return 1
    fi
    
    print_status "Creating project context file..."
    cat > ".claude/project_context.md" << 'EOF'
## Project Context & Tech Stack
You are working with a Laravel full-stack developer on the "$PROJECT_NAME" project. This is a Laravel application using:

- **Framework**: Laravel (latest version)
- **Frontend Stack**: Livewire + Alpine.js + Tailwind CSS
- **Admin Interface**: Filament
- **Database**: $DB_CONNECTION
- **Development Focus**: Full-stack Laravel development with modern frontend tools

## Developer Preferences & Coding Style

### Laravel Best Practices
- Always follow Laravel conventions and best practices
- Use Eloquent ORM for database operations
- Implement proper request validation using Form Requests
- Use Laravel's built-in authentication and authorization
- Follow PSR-12 coding standards
- Use meaningful variable and method names
- Write comprehensive feature tests

### Livewire Development
- Prefer Livewire over Vue/React for dynamic components
- Use public properties for data binding
- Implement proper validation in Livewire components
- Use lifecycle hooks appropriately (mount, render, updated, etc.)
- Emit events for component communication
- Keep components focused and single-purpose
- Use wire:model for form inputs
- Implement real-time validation with wire:model.lazy or wire:model.debounce

### Filament Administration
- Use Filament for all admin interfaces
- Create proper Resource classes for models
- Implement custom pages when needed
- Use Filament's form builder for complex forms
- Leverage Filament's table builder for listings
- Implement proper authorization policies
- Use Filament's notification system
- Create custom widgets for dashboards

### Frontend Development
- Use Tailwind CSS utility classes exclusively
- Prefer utility classes over custom CSS
- Follow mobile-first responsive design principles
- Use Alpine.js for simple client-side interactivity
- Keep Alpine.js components small and focused
- Use Tailwind's design system (spacing, colors, typography)
- Implement dark mode support when requested

### Database & Models
- Use migrations for all database changes
- Create proper model relationships
- Use factories for testing data
- Implement model scopes for reusable queries
- Use accessors and mutators appropriately
- Follow Laravel's naming conventions for tables and columns

## Available Tools
You have access to the following MCP servers:
- **Context7**: Access latest Laravel documentation and any other framework docs
- **Filesystem**: Read and edit project files
- **Database**: Query and modify database directly
- **Memory**: Remember project decisions and patterns
- **GitHub**: Manage repository operations
- **GitLab**: Manage GitLab projects, merge requests, and issues
- **Web Fetch**: Access external resources
- **Figma**: Access Figma designs, components, and design tokens (if configured)

Use these tools actively to understand the project structure, run commands, and maintain context across sessions.

## 🎨 Figma MCP Usage Guide

### ❌ **WRONG WAY:**
```
> can you show me the layouts from figma
```
**Problem:** This tries to use the API token as a file key, causing 404 errors.

### ✅ **CORRECT WAY:**
```
> can you analyze this figma file: https://www.figma.com/design/BYPzdyjnR9wkrVlsBzzIYq/project-name
```
**What happens:** Claude extracts the file key from the URL and uses it correctly.

### How to Request Figma Information

1. **Full Figma URL (Recommended):**
   ```
   > Please analyze this Figma design: https://www.figma.com/design/FILE_KEY/Project-Name
   ```

2. **Specific Frame/Component:**
   ```
   > Analyze this specific frame: https://www.figma.com/design/FILE_KEY/Project?node-id=0-1
   ```

3. **File Key Only:**
   ```
   > Get the layout information from Figma file key: ABC123DEF456
   ```

### Understanding File Keys vs API Tokens

**API Token (for authentication):**
- Format: `figd_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`
- Purpose: Authenticates requests to Figma API
- Already configured in your MCP server

**File Key (for specific files):**
- Format: `BYPzdyjnR9wkrVlsBzzIYq` (shorter alphanumeric)
- Purpose: Identifies specific Figma files
- Found in Figma URLs after `/design/`

### Best Practices for Figma Integration

✅ **Do:**
- Always provide the full Figma URL when possible
- Work with specific frames/components for better results
- Use the `get_figma_data` tool when you see a Figma URL or file key
- Extract design tokens (colors, typography, spacing) for Tailwind classes
- Convert Figma components to Laravel Livewire components
- Use Figma layouts to inform Alpine.js interactions

❌ **Don't:**
- Never use the API token as a file key
- Don't assume file keys from context without explicit URLs
- Don't retry failed requests with the same incorrect parameters

### Laravel + Figma Workflow

When working with Figma designs in this Laravel project:

1. **Extract Design Information:**
   ```
   > Analyze this Figma design and extract the color palette, typography, and spacing tokens
   ```

2. **Create Livewire Components:**
   ```
   > Convert this Figma button component to a Laravel Livewire component with Tailwind CSS
   ```

3. **Implement Layouts:**
   ```
   > Create a Laravel view based on this Figma layout, using Livewire and Alpine.js
   ```

4. **Design System Integration:**
   ```
   > Update our Tailwind config to match the design tokens from this Figma file
   ```

### Error Handling

**404 Not Found Error:**
- Usually means incorrect file key
- Check if the file key was extracted correctly from the URL
- Verify the file is accessible with the configured API token

**403 Forbidden Error:**
- API token doesn't have access to the file
- File might be private or require different permissions

### Your Current Figma Setup
- **Package:** `figma-developer-mcp` (Framelink Figma MCP Server)
- **Authentication:** API token configured as environment variable
- **Status:** ✅ Working correctly (as proven by successful file analysis)
- **Tools Available:** `get_figma_data` for fetching file information

Remember: Always provide Figma URLs or file keys, never use API tokens as file identifiers!

## Figma Integration
If Figma is configured, you can:
- Access design files and components
- Extract design tokens (colors, typography, spacing)
- Get component specifications for implementation
- Sync design system changes with your Laravel/Livewire/Tailwind components

## Project-Specific Notes
- Database connection: $DB_CONNECTION
- Project started: $(date)
- Initial setup completed with full MCP server configuration
- Figma integration: Available if token was provided

Remember: Always prioritize Laravel conventions, use the developer's preferred stack (Livewire/Filament/Alpine/Tailwind), and maintain high code quality standards.
EOF

    # Replace variables in the file
    sed -i '' "s/\$PROJECT_NAME/$PROJECT_NAME/g" ".claude/project_context.md" 2>/dev/null || sed -i "s/\$PROJECT_NAME/$PROJECT_NAME/g" ".claude/project_context.md"
    sed -i '' "s/\$DB_CONNECTION/$DB_CONNECTION/g" ".claude/project_context.md" 2>/dev/null || sed -i "s/\$DB_CONNECTION/$DB_CONNECTION/g" ".claude/project_context.md"

    if [ ! -f ".claude/project_context.md" ]; then
        print_error "Failed to create project_context.md"
        return 1
    fi

    print_status "Creating coding standards file..."
    cat > ".claude/coding_standards.md" << 'EOF'
# Coding Standards for $PROJECT_NAME

## Laravel Conventions
- Use singular model names (User, Post, not Users, Posts)
- Use plural table names (users, posts)
- Use snake_case for database columns
- Use camelCase for model attributes
- Use PascalCase for class names

## Livewire Best Practices
- Keep components focused and single-purpose
- Use public properties for data binding
- Validate input in the component
- Use lifecycle hooks appropriately
- Emit events for component communication

## Tailwind CSS Guidelines
- Use utility classes over custom CSS
- Follow mobile-first responsive design
- Use consistent spacing scale
- Leverage Tailwind's color palette
- Use component classes for repeated patterns

## Filament Conventions
- Organize resources logically
- Use proper form validation
- Implement proper authorization
- Use custom pages when needed
- Follow Filament's naming conventions
EOF

    # Replace variables in the file
    sed -i '' "s/\$PROJECT_NAME/$PROJECT_NAME/g" ".claude/coding_standards.md" 2>/dev/null || sed -i "s/\$PROJECT_NAME/$PROJECT_NAME/g" ".claude/coding_standards.md"

    print_status "Creating Claude instructions file..."
    cat > ".claude/instructions.md" << 'EOF'
# Claude Instructions for $PROJECT_NAME Laravel Project

## Project Context & Tech Stack
You are working with a Laravel full-stack developer on the "$PROJECT_NAME" project. This is a Laravel application using:

- **Framework**: Laravel (latest version)
- **Frontend Stack**: Livewire + Alpine.js + Tailwind CSS
- **Admin Interface**: Filament
- **Database**: $DB_CONNECTION
- **Development Focus**: Full-stack Laravel development with modern frontend tools

## Developer Preferences & Coding Style

### Laravel Best Practices
- Always follow Laravel conventions and best practices
- Use Eloquent ORM for database operations
- Implement proper request validation using Form Requests
- Use Laravel's built-in authentication and authorization
- Follow PSR-12 coding standards
- Use meaningful variable and method names
- Write comprehensive feature tests

### Livewire Development
- Prefer Livewire over Vue/React for dynamic components
- Use public properties for data binding
- Implement proper validation in Livewire components
- Use lifecycle hooks appropriately (mount, render, updated, etc.)
- Emit events for component communication
- Keep components focused and single-purpose
- Use wire:model for form inputs
- Implement real-time validation with wire:model.lazy or wire:model.debounce

### Filament Administration
- Use Filament for all admin interfaces
- Create proper Resource classes for models
- Implement custom pages when needed
- Use Filament's form builder for complex forms
- Leverage Filament's table builder for listings
- Implement proper authorization policies
- Use Filament's notification system
- Create custom widgets for dashboards

### Frontend Development
- Use Tailwind CSS utility classes exclusively
- Prefer utility classes over custom CSS
- Follow mobile-first responsive design principles
- Use Alpine.js for simple client-side interactivity
- Keep Alpine.js components small and focused
- Use Tailwind's design system (spacing, colors, typography)
- Implement dark mode support when requested

### Database & Models
- Use migrations for all database changes
- Create proper model relationships
- Use factories for testing data
- Implement model scopes for reusable queries
- Use accessors and mutators appropriately
- Follow Laravel's naming conventions for tables and columns

## Available Tools
You have access to the following MCP servers:
- **Context7**: Access latest Laravel documentation and any other framework docs
- **Filesystem**: Read and edit project files
- **Database**: Query and modify database directly
- **Memory**: Remember project decisions and patterns
- **GitHub**: Manage repository operations
- **GitLab**: Manage GitLab projects, merge requests, and issues
- **Web Fetch**: Access external resources
- **Figma**: Access Figma designs, components, and design tokens (if configured)

Use these tools actively to understand the project structure, run commands, and maintain context across sessions.

## Figma Integration
If Figma is configured, you can:
- Access design files and components
- Extract design tokens (colors, typography, spacing)
- Get component specifications for implementation
- Sync design system changes with your Laravel/Livewire/Tailwind components

## Project-Specific Notes
- Database connection: $DB_CONNECTION
- Project started: $(date)
- Initial setup completed with full MCP server configuration
- Figma integration: Available if token was provided

Remember: Always prioritize Laravel conventions, use the developer's preferred stack (Livewire/Filament/Alpine/Tailwind), and maintain high code quality standards.
EOF

    # Replace variables in the file
    sed -i '' "s/\$PROJECT_NAME/$PROJECT_NAME/g" ".claude/instructions.md" 2>/dev/null || sed -i "s/\$PROJECT_NAME/$PROJECT_NAME/g" ".claude/instructions.md"
    sed -i '' "s/\$DB_CONNECTION/$DB_CONNECTION/g" ".claude/instructions.md" 2>/dev/null || sed -i "s/\$DB_CONNECTION/$DB_CONNECTION/g" ".claude/instructions.md"

    print_status "Creating memory prompts file..."
    cat > ".claude/memory_prompts.md" << 'EOF'
# Memory Initialization for $PROJECT_NAME

## Project Information
- **Project Name**: $PROJECT_NAME
- **Tech Stack**: Laravel + Livewire + Filament + Alpine.js + Tailwind CSS
- **Database**: $DB_CONNECTION
- **Main Developer**: Laravel Full-Stack Developer
- **Preferred Tools**: Livewire, Filament, Alpine, Tailwind

## Development Preferences
- Follow Laravel best practices and conventions
- Use Livewire for dynamic components over Vue/React
- Prefer Tailwind utility classes over custom CSS
- Use Filament for admin interfaces
- Write feature tests for new functionality
- Follow PSR-12 coding standards

## Project Structure Notes
- Custom Livewire components in app/Http/Livewire/
- Filament resources in app/Filament/Resources/
- Alpine.js components in resources/js/
- Custom Tailwind components in resources/css/

## Remember These Decisions
(This section will be updated as the project evolves)
- [Date] - Decision made about X
- [Date] - Architectural choice for Y
- [Date] - Code pattern established for Z

## Common Tasks for This Project
- Creating Livewire components with proper validation
- Setting up Filament resource pages
- Implementing Alpine.js interactivity
- Database migrations and model relationships
- Feature testing with PHPUnit
EOF

    # Replace variables in the file
    sed -i '' "s/\$PROJECT_NAME/$PROJECT_NAME/g" ".claude/memory_prompts.md" 2>/dev/null || sed -i "s/\$PROJECT_NAME/$PROJECT_NAME/g" ".claude/memory_prompts.md"
    sed -i '' "s/\$DB_CONNECTION/$DB_CONNECTION/g" ".claude/memory_prompts.md" 2>/dev/null || sed -i "s/\$DB_CONNECTION/$DB_CONNECTION/g" ".claude/memory_prompts.md"
    
    # Verify all files were created successfully
    local files_created=0
    for file in "project_context.md" "coding_standards.md" "instructions.md" "memory_prompts.md"; do
        if [ -f ".claude/$file" ]; then
            ((files_created++))
        else
            print_error "Failed to create .claude/$file"
        fi
    done
    
    if [ $files_created -eq 4 ]; then
        print_success "Project prompts created! ($files_created/4 files)"
    else
        print_error "Only $files_created/4 project files were created successfully"
        return 1
    fi
}

# Create useful aliases and shortcuts
create_shortcuts() {
    print_status "Creating useful shortcuts..."
    
    # Ensure we're in the project directory
    PROJECT_PATH="$PWD"
    cd "$PROJECT_PATH"
    
    # Verify .claude directory exists
    if [ ! -d ".claude" ]; then
        print_error ".claude directory does not exist, cannot create shortcuts"
        return 1
    fi
    
    cat > ".claude/shortcuts.sh" << 'EOF'
#!/bin/bash

# Laravel Development Shortcuts for Claude Code

# Artisan shortcuts
alias pa='php artisan'
alias pam='php artisan migrate'
alias pams='php artisan migrate --seed'
alias par='php artisan route:list'
alias pat='php artisan test'
alias paq='php artisan queue:work'

# Livewire shortcuts
alias make-livewire='php artisan make:livewire'
alias make-component='php artisan make:component'

# Asset shortcuts
alias npm-dev='npm run dev'
alias npm-watch='npm run watch'
alias npm-build='npm run build'

# Git shortcuts
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline'

# Project shortcuts
alias serve='php artisan serve'
alias tinker='php artisan tinker'
alias fresh='php artisan migrate:fresh --seed'

echo "🚀 Laravel development shortcuts loaded!"
echo "Use 'pa' instead of 'php artisan', 'pam' for migrate, etc."
EOF

    chmod +x ".claude/shortcuts.sh"
    
    # Verify the file was created
    if [ -f ".claude/shortcuts.sh" ] && [ -x ".claude/shortcuts.sh" ]; then
        print_success "Shortcuts created! Source .claude/shortcuts.sh to use them."
    else
        print_error "Failed to create shortcuts.sh file"
        return 1
    fi
}

# Generate project documentation
generate_docs() {
    print_status "Generating project documentation..."
    
    # Ensure we're in the project directory
    PROJECT_PATH="$PWD"
    PROJECT_NAME=$(basename "$PROJECT_PATH")
    cd "$PROJECT_PATH"
    
    # Verify .claude directory exists
    if [ ! -d ".claude" ]; then
        print_error ".claude directory does not exist, cannot create documentation"
        return 1
    fi
    
    cat > ".claude/README.md" << 'EOF'
# Claude Code Setup for $PROJECT_NAME

This Laravel project has been configured with Claude Code and the following MCP servers:

## Available MCP Servers

### Global Servers (shared across all projects)
1. **GitHub** - Repository access and management
2. **Memory** - Shared knowledge base across projects
3. **Context7** - Latest documentation access
4. **Web Fetch** - External API and resource access

### Project-Specific Servers
1. **Filesystem** - Access to this project's files
2. **Database** - Direct database access for this project
3. **Laravel DebugBar** (if installed) - Debug information

## Usage
1. Open Claude Code in this project directory
2. All MCP servers are automatically configured
3. Use natural language to interact with your codebase
4. Ask Claude to help with Laravel, Livewire, Filament, and Tailwind tasks

## Environment
- Laravel Framework
- Livewire for dynamic components
- Filament for admin interface
- Alpine.js for frontend interactivity
- Tailwind CSS for styling

## Getting Started
Run `source .claude/shortcuts.sh` to load helpful aliases.

## Tips
- Global servers work across all your Laravel projects
- Use project names when referencing files: "Read .env from $PROJECT_NAME"
- GitHub access works for all your repositories
- Memory is shared, so decisions in one project can inform others

Happy coding! 🚀
EOF

    # Replace variables in the file
    sed -i '' "s/\$PROJECT_NAME/$PROJECT_NAME/g" ".claude/README.md" 2>/dev/null || sed -i "s/\$PROJECT_NAME/$PROJECT_NAME/g" ".claude/README.md"

    # Verify the file was created
    if [ -f ".claude/README.md" ]; then
        print_success "Documentation generated!"
    else
        print_error "Failed to create README.md file"
        return 1
    fi
}

# Main installation function
main() {
    echo "========================================="
    echo "= Laravel Claude Code Setup Script v2.1 ="
    echo "========================================="
    echo ""
    
    # Store the original directory
    ORIGINAL_DIR="$PWD"
    
    # Pre-flight checks
    check_laravel_project
    check_claude_code
    check_node
    
    # Collect tokens and keys
    collect_tokens
    
    # Parse environment
    parse_env
    
    # Create MCP directory
    create_mcp_directory
    
    # Install MCP servers (these change directories, so we need to return)
    install_context7
    cd "$ORIGINAL_DIR"
    
    install_filesystem
    cd "$ORIGINAL_DIR"
    
    install_database
    cd "$ORIGINAL_DIR"
    
    install_web_fetch
    cd "$ORIGINAL_DIR"
    
    install_github
    cd "$ORIGINAL_DIR"

    install_gitlab
    cd "$ORIGINAL_DIR"

    install_memory
    cd "$ORIGINAL_DIR"
    
    install_debugbar_mcp
    cd "$ORIGINAL_DIR"

    install_figma
    cd "$ORIGINAL_DIR"
    
    # Generate database configuration
    generate_database_config
    cd "$ORIGINAL_DIR"
    
    # Create project-specific files (these MUST run in the project directory)
    print_status "Creating project-specific files in: $ORIGINAL_DIR"
    
    if create_project_prompts; then
        print_success "Project prompts created successfully"
    else
        print_error "Failed to create project prompts"
        exit 1
    fi
    
    if create_shortcuts; then
        print_success "Shortcuts created successfully"
    else
        print_error "Failed to create shortcuts"
        exit 1
    fi
    
    if generate_docs; then
        print_success "Documentation created successfully"
    else
        print_error "Failed to create documentation"
        exit 1
    fi
    
    # Configure Claude Code MCP servers
    configure_claude_mcp
    cd "$ORIGINAL_DIR"
    
    # Final verification
    print_status "Verifying project files..."
    if [ -d ".claude" ] && [ -f ".claude/shortcuts.sh" ] && [ -f ".claude/project_context.md" ]; then
        print_success "All project files created successfully in $(pwd)/.claude/"
        ls -la .claude/
    else
        print_error "Project files verification failed"
        exit 1
    fi
    
    echo ""
    echo "======================================"
    print_success "Setup completed successfully!"
    echo "======================================"
    echo ""
    print_status "🚀 Claude Code is now fully configured with MCP servers!"
    echo ""
    print_status "📋 Installed MCP Servers:"
    echo ""
    echo "  Global Servers (shared across all projects):"
    claude mcp list | grep -E "^(github|memory|context7|webfetch):" | sed 's/^/    ✅ /' || true
    echo ""
    echo "  Project-Specific Servers for $PROJECT_NAME:"
    claude mcp list | grep -E "^(filesystem|database|debugbar)-$PROJECT_ID" | sed 's/^/    ✅ /' || true
    echo ""
    print_status "Next steps:"
    echo "1. Restart Claude Code to ensure all servers are loaded"
    echo "2. Load helpful aliases: source .claude/shortcuts.sh"
    echo "3. Test MCP servers with: 'Can you list available MCP servers and read my .env file?'"
    echo "4. Try: 'Show me the project structure' or 'What's in my database?'"
    echo "5. Ask Claude to remember important project decisions"
    echo "6. Start coding with full AI assistance!"
    echo ""
    print_warning "💡 Pro tip: Use 'source .claude/shortcuts.sh' for Laravel aliases (pa, pam, par, etc.)"
    echo ""
    print_success "🎉 Your Laravel + Livewire + Filament + Alpine + Tailwind development environment is ready!"
    echo ""
    
    # Count successful MCP servers
    GLOBAL_MCP_COUNT=$(claude mcp list | grep -E "^(github|gitlab|memory|context7|webfetch|figma):" | wc -l | tr -d ' ')
    PROJECT_MCP_COUNT=$(claude mcp list | grep -E "^(filesystem|database|debugbar)-$PROJECT_ID" | wc -l | tr -d ' ')
    TOTAL_MCP_COUNT=$(claude mcp list | wc -l | tr -d ' ')
    
    if [ "$GLOBAL_MCP_COUNT" -ge 2 ] && [ "$PROJECT_MCP_COUNT" -ge 1 ]; then
        print_success "✅ All core MCP servers installed successfully!"
        print_status "Global servers: $GLOBAL_MCP_COUNT | Project servers: $PROJECT_MCP_COUNT | Total: $TOTAL_MCP_COUNT"
    else
        print_warning "⚠️ Some MCP servers may have failed to install"
        print_status "Global servers: $GLOBAL_MCP_COUNT | Project servers: $PROJECT_MCP_COUNT | Total: $TOTAL_MCP_COUNT"
        print_status "Check the output above for any error messages"
    fi
    
    # GitHub token configuration reminder
    if [ "$GITHUB_AUTH_METHOD" = "token" ] && [ ! -z "$GITHUB_TOKEN" ]; then
        CONFIG_FILE="$HOME/.claude.json"
        if [ -f "$CONFIG_FILE" ]; then
            # Check if token is properly configured in project-specific config
            PROJECT_HAS_TOKEN=$(jq -r --arg project "$PROJECT_PATH" \
                '.projects[$project].mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN // "not_found"' \
                "$CONFIG_FILE" 2>/dev/null)
            
            if [ "$PROJECT_HAS_TOKEN" = "not_found" ] || [ -z "$PROJECT_HAS_TOKEN" ]; then
                echo ""
                print_warning "⚠️  GitHub token may need manual configuration"
                echo "If private repository access doesn't work, edit ~/.claude.json"
                echo "and ensure the token is in the project-specific GitHub config:"
                echo "projects.'$PROJECT_PATH'.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN"
            fi
        fi
    fi
}

# Run the main function
main "$@"