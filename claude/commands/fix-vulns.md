# Scan and Fix Vulnerabilities

> Use this command when fixing security vulnerabilities in Docker images or Dockerfiles.

Run the `scan_vulns` function to scan for vulnerabilities, fix any issues found, and verify the fixes.

## Steps

1. **Scan for vulnerabilities**: Run the vulnerability scan to identify security issues. ONLY use the `scan_vulns` command - no other commands are permitted for scanning.
2. **Analyze the results**: Review the vulnerability scan output
3. **Fix vulnerabilities**: Apply fixes for each identified vulnerability
4. **Verify fixes**: Re-run the scan to confirm all vulnerabilities have been resolved


## Usage

```bash
scan_vulns [--dockerfile|-f <path>] [--dir|-d <directory>]
```
