#!/usr/bin/env bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}NordVPN Flake Update Script${NC}"
echo "=============================="

# Function to get the latest NordVPN version
get_latest_nordvpn_version() {
    echo -e "${YELLOW}Fetching latest NordVPN version...${NC}"
    local versions=$(curl -s https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/ | \
        grep -o 'nordvpn_[0-9]\+\.[0-9]\+\.[0-9]\+_' | \
        sed 's/nordvpn_//;s/_$//' | \
        sort -V | \
        tail -1)
    echo "$versions"
}

# Function to download a file with verification
download_file() {
    local url=$1
    local dest=$2
    local desc=$3
    
    echo -e "${YELLOW}Downloading ${desc}...${NC}"
    echo "URL: $url"
    echo "Destination: $dest"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$dest")"
    
    # Download with wget
    if wget -O "$dest.tmp" "$url"; then
        mv "$dest.tmp" "$dest"
        echo -e "${GREEN}✓ Successfully downloaded ${desc}${NC}"
        return 0
    else
        rm -f "$dest.tmp"
        echo -e "${RED}✗ Failed to download ${desc}${NC}"
        return 1
    fi
}

# Get current version from nordvpn.nix
CURRENT_VERSION=$(grep -oP 'version = "\K[^"]+' nordvpn.nix 2>/dev/null || echo "unknown")
echo "Current version in nordvpn.nix: $CURRENT_VERSION"

# Get latest version
LATEST_VERSION=$(get_latest_nordvpn_version)
echo "Latest available version: $LATEST_VERSION"

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    echo -e "${GREEN}Already up to date!${NC}"
    read -p "Do you want to re-download anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Create vendor directory structure
echo -e "${YELLOW}Creating vendor directory structure...${NC}"
mkdir -p vendor/nordvpn/{x86_64-linux,aarch64-linux} vendor/libxml2

# Download NordVPN packages
echo ""
echo "Downloading NordVPN packages..."
echo "==============================="

# x86_64 package
download_file \
    "https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/nordvpn_${LATEST_VERSION}_amd64.deb" \
    "vendor/nordvpn/x86_64-linux/nordvpn_${LATEST_VERSION}_amd64.deb" \
    "NordVPN x86_64 package"

# aarch64 package  
download_file \
    "https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn/nordvpn_${LATEST_VERSION}_arm64.deb" \
    "vendor/nordvpn/aarch64-linux/nordvpn_${LATEST_VERSION}_arm64.deb" \
    "NordVPN aarch64 package"

# Download libxml2 legacy package
echo ""
echo "Downloading libxml2 legacy package..."
echo "====================================="

# Check if we need to rename the existing libxml2 file
LIBXML2_ORIG="libxml2_2.9.14+dfsg-1.3~deb12u1_amd64.deb"
LIBXML2_SAFE="libxml2_2.9.14_dfsg-1.3_deb12u1_amd64.deb"

if [ -f "vendor/libxml2/$LIBXML2_SAFE" ] && [ ! -f "vendor/libxml2/$LIBXML2_ORIG" ]; then
    echo -e "${YELLOW}libxml2 already using safe filename${NC}"
else
    download_file \
        "http://ftp.debian.org/debian/pool/main/libx/libxml2/$LIBXML2_ORIG" \
        "vendor/libxml2/$LIBXML2_ORIG" \
        "libxml2 legacy package"
    
    # Rename to remove special characters
    if [ -f "vendor/libxml2/$LIBXML2_ORIG" ]; then
        echo -e "${YELLOW}Renaming libxml2 file to remove special characters...${NC}"
        mv "vendor/libxml2/$LIBXML2_ORIG" "vendor/libxml2/$LIBXML2_SAFE"
    fi
fi

# Clean up old versions
echo ""
echo -e "${YELLOW}Cleaning up old versions...${NC}"

# Remove old NordVPN packages
find vendor/nordvpn -name "nordvpn_*.deb" ! -name "*${LATEST_VERSION}*" -delete -print | \
    while read -r file; do
        echo -e "${RED}✗ Removed old file: $file${NC}"
    done

# Update nordvpn.nix with new version
if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
    echo ""
    echo -e "${YELLOW}Updating nordvpn.nix with new version...${NC}"
    
    # Update version
    sed -i "s/version = \"${CURRENT_VERSION}\"/version = \"${LATEST_VERSION}\"/" nordvpn.nix
    
    # Update file references in the nix file
    sed -i "s/nordvpn_${CURRENT_VERSION}_amd64\.deb/nordvpn_${LATEST_VERSION}_amd64.deb/g" nordvpn.nix
    sed -i "s/nordvpn_${CURRENT_VERSION}_arm64\.deb/nordvpn_${LATEST_VERSION}_arm64.deb/g" nordvpn.nix
    
    echo -e "${GREEN}✓ Updated nordvpn.nix to version ${LATEST_VERSION}${NC}"
fi

# Show summary
echo ""
echo "Summary"
echo "======="
echo -e "${GREEN}✓ Vendor directory updated successfully${NC}"
echo "Total size: $(du -sh vendor/ | cut -f1)"
echo ""
echo "Downloaded files:"
find vendor -name "*.deb" -type f | sort

# Test build
echo ""
read -p "Do you want to test the build? (Y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo -e "${YELLOW}Testing build...${NC}"
    if nix build .#nordvpn --no-link; then
        echo -e "${GREEN}✓ Build successful!${NC}"
        
        # Test version
        echo -e "${YELLOW}Testing version...${NC}"
        VERSION_OUTPUT=$(nix run .#nordvpn -- --version 2>&1 | head -1)
        echo "Version output: $VERSION_OUTPUT"
    else
        echo -e "${RED}✗ Build failed!${NC}"
        exit 1
    fi
fi

# Git status
echo ""
echo -e "${YELLOW}Git status:${NC}"
git status --porcelain vendor/ nordvpn.nix

echo ""
echo -e "${GREEN}Update complete!${NC}"
echo "Don't forget to:"
echo "  1. Review the changes"
echo "  2. Test the build thoroughly"
echo "  3. Commit the changes with: git add vendor/ nordvpn.nix && git commit -m 'Update NordVPN to ${LATEST_VERSION}'"