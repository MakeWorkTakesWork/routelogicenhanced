# Installing Salesforce CLI

The Salesforce CLI is required to deploy and test the RouteLogic security components. Here are your installation options:

## Option 1: Install via npm (Recommended)

```bash
# Install Salesforce CLI globally
npm install -g @salesforce/cli

# Verify installation
sf --version
# or
sfdx --version
```

## Option 2: Install via Homebrew (macOS)

```bash
# Install via Homebrew
brew install salesforce/tap/salesforce-cli

# Verify installation
sf --version
```

## Option 3: Download Installer

1. Visit: https://developer.salesforce.com/tools/salesforcecli
2. Download the installer for macOS
3. Run the installer
4. Restart your terminal

## After Installation

1. **Verify Installation:**
   ```bash
   sf --version
   # Should show something like: @salesforce/cli/2.23.0
   ```

2. **Login to Your Sandbox:**
   ```bash
   # For sandbox
   sf org login web --alias YOUR_SANDBOX_ALIAS --instance-url https://test.salesforce.com
   
   # For production (be careful!)
   sf org login web --alias YOUR_PROD_ALIAS
   ```

3. **List Connected Orgs:**
   ```bash
   sf org list
   ```

## Quick Install Script

Run this to install via npm:

```bash
#!/bin/bash
echo "Installing Salesforce CLI..."
npm install -g @salesforce/cli

echo "Verifying installation..."
sf --version

echo "Installation complete!"
echo "Now login to your sandbox:"
echo "sf org login web --alias mysandbox --instance-url https://test.salesforce.com"
```

## Next Steps

After installing:

1. Login to your sandbox
2. Run the Platform Cache check:
   ```bash
   cd /Users/johnsweazey/routelogicenhanced4.0.0
   ./scripts/check-platform-cache.sh YOUR_SANDBOX_ALIAS
   ```

Would you like me to guide you through the installation?