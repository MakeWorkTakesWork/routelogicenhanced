# Manual Sandbox Login Steps

## Option 1: Command Line (Recommended)

Run this command and complete the login in your browser:

```bash
sf org login web --alias mysandbox --instance-url https://test.salesforce.com
```

**Important:**
- A browser window will open
- Use your **SANDBOX** credentials (not production)
- The URL should be `test.salesforce.com`
- After login, you'll see "Successfully authorized" in the browser
- Return to terminal and press Enter

## Option 2: If Browser Doesn't Open

Try with explicit browser:

```bash
sf org login web --alias mysandbox --instance-url https://test.salesforce.com --browser chrome
```

## Option 3: Device Flow (No Browser)

```bash
sf org login device --alias mysandbox --instance-url https://test.salesforce.com
```

This will give you a code to enter at https://test.salesforce.com/setup/connect

## Verify Connection

After successful login, verify with:

```bash
# Check connected orgs
sf org list

# Display org details
sf org display --target-org mysandbox
```

You should see your sandbox listed.

## Common Issues

### "Invalid client credentials"
- Make sure you're using sandbox URL: `https://test.salesforce.com`
- Not: `https://login.salesforce.com`

### "Authentication failure"
- Ensure you're using sandbox username (usually has `.sandboxname` suffix)
- Example: `user@company.com.mysandbox`

### Browser doesn't open
- Copy the URL from terminal and open manually
- Or use the device flow option above

## After Successful Login

Run the Platform Cache test:

```bash
cd /Users/johnsweazey/routelogicenhanced4.0.0
./scripts/check-platform-cache.sh mysandbox
```

Need help? The login process should:
1. Open browser to Salesforce login
2. You login with sandbox credentials
3. Authorize the CLI
4. Return to terminal
5. Connection confirmed!