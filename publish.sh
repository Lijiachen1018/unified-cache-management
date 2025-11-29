#!/bin/bash
# This script replicates the GitHub Actions publish workflow
# Usage: 
# firstly create a personal access token for GitHub , dockerhub and PyPI
#       
# Secondly, set environment variables: TAG_NAME, GITHUB_TOKEN, PYPI_API_TOKEN, HTTP_PROXY, HTTPS_PROXY, etc.
# export PYPI_API_TOKEN="your_pypi_token"
# export PYPI_REPO="testpypi or pypi"
# export HTTP_PROXY="http://proxy:port"
# export HTTPS_PROXY="http://proxy:port"
# export DOCKER_USERNAME="your_username, eg. unifiedcachemanagement"
# export DOCKER_PASSWORD="your_password, dockerhub token created in first step"
# export DOCKER_HUB_REPO="your_dockerhub_repo_name, eg. unifiedcachemanagement/ucm"
# export GITHUB_USERNAME="your_github_username"

# Thirdly, login to GitHub, dockerhub with your credentials created in the first step
#       docker login
#
# Finally create a release with the tag name
#       ./publish.sh [TAG_NAME]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Get tag name from argument
if [ $# -ge 1 ]; then
    TAG_NAME="$1"
elif [ -n "${TAG_NAME:-}" ]; then
    # Use environment variable
    :
else
    error "No tag name provided. Usage: $0 [TAG_NAME] or set TAG_NAME environment variable"

fi

info "Using tag: $TAG_NAME"

# Validate tag format
if [[ ! "$TAG_NAME" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(rc[0-9]+)?$ ]]; then
    error "Invalid tag format. Expected: v[0-9]+.[0-9]+.[0-9]+ or v[0-9]+.[0-9]+.[0-9]+rc[0-9]+"
fi

# Get workspace directory (script directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${WORKSPACE:-$SCRIPT_DIR}"
echo "WORKSPACE: $WORKSPACE"
echo "SCRIPT_DIR: $SCRIPT_DIR"

# Required environment variables
REQUIRED_VARS=(
    "PYPI_API_TOKEN"
)

# Optional but recommended
OPTIONAL_VARS=(
    "HTTP_PROXY"
    "HTTPS_PROXY"
    "DOCKER_USERNAME"
    "DOCKER_PASSWORD"
    "PYPI_REPO"
    "PIP_INDEX_URL"
    "DOCKER_HUB_REPO"
    "GITHUB_USERNAME"
)

# Check required variables
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        error "Required environment variable $var is not set"
    fi
done

# Warn about missing optional variables
for var in "${OPTIONAL_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        warn "Optional environment variable $var is not set"
    fi
done

# Set defaults
PYPI_REPO="${PYPI_REPO:-testpypi}"
PIP_INDEX_URL="${PIP_INDEX_URL:-https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple}"
DOCKER_IMAGE="${DOCKER_IMAGE:-vllm/vllm-openai:v0.9.2}"
DOCKER_HUB_REPO="${DOCKER_HUB_REPO}"
GITHUB_USERNAME="${GITHUB_USERNAME}"
DOCKER_USERNAME="${DOCKER_USERNAME}"

check_github_login() {
    info "Checking if logged in to GitHub..."
    # Check if gh auth status succeeds (exit code 0 means logged in)
    if ! gh auth status &>/dev/null; then
        error "Not logged in to GitHub. use 'gh auth login' to login to GitHub"
    fi
    # Optionally verify username matches (gh auth status outputs to stderr)
    if ! gh auth status 2>&1 | grep -q "$GITHUB_USERNAME"; then
        error "Logged in to GitHub but username doesn't match $GITHUB_USERNAME"
    fi
    info "Logged in to GitHub"
}

# Function: Create GitHub Release
create_release() {
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI (gh) not found. Skipping release creation. Install it from: https://cli.github.com/"
    fi

    # Export proxy settings for gh CLI
    [ -n "${HTTP_PROXY:-}" ] && export HTTP_PROXY
    [ -n "${HTTPS_PROXY:-}" ] && export HTTPS_PROXY

    # Check if release already exists
    if gh release view "$TAG_NAME" &>/dev/null; then
        error "Release $TAG_NAME already exists. Skipping creation."
    fi
    
    local repo
    repo="$(git remote get-url origin | sed 's/.*github.com[:/]\([^.]*\).*/\1/')"
    git tag -a "$TAG_NAME" -m "Release version $TAG_NAME"
    git push origin "$TAG_NAME"
    # Create release (draft and prerelease if it's an RC)
    if [[ "$TAG_NAME" =~ rc[0-9]+$ ]]; then
        gh release create "$TAG_NAME" \
            --generate-notes \
            --draft \
            --prerelease \
            --title "$TAG_NAME" \
            --repo "$repo" || {
            error "Failed to create release. Check network connection and proxy settings."
        }
    else
        gh release create "$TAG_NAME" \
            --generate-notes \
            --draft \
            --title "$TAG_NAME" \
            --repo "$repo" || {
            error "Failed to create release. Check network connection and proxy settings."
        }
    fi
}

rename_version() {
    if [ ! -f "setup.py" ]; then
        error "setup.py not found in $WORKSPACE"
    fi
    
    # Update version in setup.py
    if [ -f "setup.py" ]; then
        info "Updating version in setup.py to $TAG_NAME"
        sed -i "s/version=\".*\"/version=\"${TAG_NAME#v}\"/g" setup.py || error "Failed to update version in setup.py"
    fi
}

# restore_version() {
#     # Restore setup.py if backup exists
#     if [ -f "setup.py.bak" ]; then
#         mv setup.py.bak setup.py || error "Failed to restore version in setup.py"
#     fi
# }

# Function: Build wheel and upload to PyPI
build_and_upload_wheel() {
    info "Building wheel and uploading to PyPI"

    
    # Build wheel in Docker
    info "Building wheel in Docker container..."
    docker run --rm \
        --network host \
        ${HTTP_PROXY:+--env HTTP_PROXY="$HTTP_PROXY"} \
        ${HTTPS_PROXY:+--env HTTPS_PROXY="$HTTPS_PROXY"} \
        -v "$WORKSPACE:/workspace/unified-cache-management" \
        -w /workspace/unified-cache-management \
        --entrypoint /bin/bash \
        --name release_local_test \
        "$DOCKER_IMAGE" \
        -c "
            set -euo pipefail
            git config --global http.sslVerify false || true
            ${HTTP_PROXY:+git config --global http.proxy \"$HTTP_PROXY\"}
            ${HTTPS_PROXY:+git config --global https.proxy \"$HTTPS_PROXY\"}
            git config --global http.version HTTP/1.1 || true
            export PLATFORM=cuda
            rm -rf dist/
            pip install --upgrade pip ${HTTP_PROXY:+--proxy \"$HTTP_PROXY\"} -i \"$PIP_INDEX_URL\"
            pip install twine ${HTTP_PROXY:+--proxy \"$HTTP_PROXY\"} -i \"$PIP_INDEX_URL\"
	    pip install build
            python3 -m build --sdist .
            echo \"[$PYPI_REPO]\" >> ~/.pypirc
            echo \"username=__token__\" >> ~/.pypirc
            echo \"password=$PYPI_API_TOKEN\" >> ~/.pypirc
            ${HTTP_PROXY:+export HTTP_PROXY=\"$HTTP_PROXY\"}
            ${HTTPS_PROXY:+export HTTPS_PROXY=\"$HTTPS_PROXY\"}
            echo \"Uploading wheels from dist/:\"
	    python3 -m twine upload --repository \"$PYPI_REPO\" --skip-existing dist/*
        " || error "Failed to build and upload wheel."
    
}

# Function: Find wheel file
find_wheel() {
    local wheel_file
    wheel_file=$(find "$WORKSPACE/dist" -name "*.whl" -type f 2>/dev/null | head -n 1)
    
    if [ -z "$wheel_file" ]; then
        error "No wheel file found in $WORKSPACE/dist"
    fi
    
    echo "$wheel_file"
}

# Function: Upload wheel to GitHub Release
upload_wheel_to_release() {
    info "Uploading wheel to GitHub release"
    local wheel_file
    wheel_file=$(find_wheel)
    local wheel_name
    wheel_name=$(basename "$wheel_file")
    
    info "Found wheel: $wheel_name"
    
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI (gh) not found. Skipping wheel upload."
    fi
    
    # Export proxy settings for gh CLI
    [ -n "${HTTP_PROXY:-}" ] && export HTTP_PROXY
    [ -n "${HTTPS_PROXY:-}" ] && export HTTPS_PROXY
    
    local repo
    repo="$(git remote get-url origin | sed 's/.*github.com[:/]\([^.]*\).*/\1/')"
    
    # Upload to release
    gh release upload "$TAG_NAME" "$wheel_file" \
        --repo "$repo" \
        --clobber || {
        error "Failed to upload wheel to release. Check network connection and proxy settings."
    }
}

check_docker_login() {
    if docker info | grep "Username: $DOCKER_USERNAME"; then
        info "Already logged in to Docker Hub"
        return 0
    fi
    error "Not logged in to Docker Hub. use 'docker login' to login to Docker Hub"
}
# Function: Build and push Docker image
build_and_push_docker() {
    info "Building and pushing Docker image"
    
    # Configure git proxy if needed
    if [ -n "${HTTP_PROXY:-}" ]; then
        git config --global http.proxy "$HTTP_PROXY" || true
        git config --global https.proxy "${HTTPS_PROXY:-$HTTP_PROXY}" || true
        git config --global http.version HTTP/1.1 || true
    fi
    
    # Build Docker image
    info "Building Docker image: $DOCKER_HUB_REPO:$TAG_NAME"
    docker build \
        --network host \
        ${HTTP_PROXY:+--build-arg HTTP_PROXY="$HTTP_PROXY"} \
        ${HTTPS_PROXY:+--build-arg HTTPS_PROXY="${HTTPS_PROXY:-$HTTP_PROXY}"} \
        -t "$DOCKER_HUB_REPO:$TAG_NAME" \
        -f docker/Dockerfile \
        . || {
        error "Failed to build Docker image. Continuing..."
    }
    
    # Tag as latest
    docker tag "$DOCKER_HUB_REPO:$TAG_NAME" "$DOCKER_HUB_REPO:latest"
    
    # Push images
    info "Pushing Docker images..."
    docker push "$DOCKER_HUB_REPO:$TAG_NAME" || warn "Failed to push $DOCKER_HUB_REPO:$TAG_NAME"
    docker push "$DOCKER_HUB_REPO:latest" || warn "Failed to push $DOCKER_HUB_REPO:latest"
}


# Main execution
main() {

    check_docker_login

    # check_github_login


    info "====================== All pre-checks passed ======================"
    info "========== Starting publish workflow for tag: $TAG_NAME ==========="
    # Step 1: Create GitHub Release
    info "============= Creating GitHub Release ========================="
    # create_release

    rename_version

    # Step 2: Build wheel and upload to PyPI
    info "========== Building wheel and uploading to PyPI ==================="
    build_and_upload_wheel
    
    # Step 3: Upload wheel to GitHub Release
    info "========== Uploading wheel to GitHub Release ======================"
    upload_wheel_to_release
    
    # Step 4: Build and push Docker image
    info "============ Building and pushing Docker image ===================="
    build_and_push_docker

    # info "============ Restoring version in setup.py ========================="
    # restore_version

    info "============ Publish workflow completed successfully ==============="
    info "=============== Tag: $TAG_NAME ====================================="
}

# Run main function
main "$@"

