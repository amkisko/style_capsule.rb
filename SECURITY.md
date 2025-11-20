# SECURITY

## Supported Versions

We actively support the following versions with security updates:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Security Considerations

### Input Validation

StyleCapsule validates all inputs to prevent security vulnerabilities:

- **CSS Content**: Maximum size limit of 1MB to prevent DoS attacks
- **Scope IDs**: Must be alphanumeric with hyphens/underscores only (max 100 characters)
- **File Paths**: Validated to prevent path traversal attacks

### File Writing Security

When using file-based caching, StyleCapsule:

- Validates all filenames to prevent path traversal (`../` sequences)
- Restricts filenames to safe characters (alphanumeric, dots, hyphens, underscores)
- Enforces maximum filename length (255 characters)
- Rejects null bytes and other dangerous characters

### XSS Prevention

StyleCapsule uses Rails' built-in HTML escaping:

- CSS content is rendered via Rails `content_tag` which automatically escapes content
- Scope IDs in HTML attributes are escaped by Rails helpers
- User-provided CSS should still be validated by application code

**Important**: While StyleCapsule provides basic protection, applications should:
- Validate CSS content from untrusted sources
- Use Content Security Policy (CSP) headers
- Sanitize user-generated CSS if allowing user input

### Memory Safety

- CSS content is limited to 1MB per component to prevent memory exhaustion
- Thread-local caches are cleared per-request in development
- Process-wide caches are cleared on code reload in development

### Ruby Version Requirements

StyleCapsule requires **Ruby >= 3.0** for security reasons:
- Ruby 2.7 reached end-of-life in March 2023
- Ruby 3.0+ includes important security fixes
- Using EOL Ruby versions exposes applications to unpatched vulnerabilities

## Reporting a Vulnerability

If you discover a security vulnerability, please **do not** open a public issue. Instead:

1. **Email**: contact@kiskolabs.com
2. **Subject**: `[SECURITY] style_capsule vulnerability report`
3. **Include**:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will:
- Acknowledge receipt within 48 hours
- Provide an initial assessment within 7 days
- Keep you informed of our progress
- Credit you in the security advisory (if desired)

## Security Best Practices for Users

1. **Keep Ruby and Rails Updated**: Use supported versions with security patches
2. **Validate User Input**: Don't trust user-provided CSS without validation
3. **Use Content Security Policy**: Configure CSP headers to restrict inline styles
4. **Review Generated Files**: Periodically review files in `app/assets/build/capsules/`
5. **Monitor File System**: Set up alerts for unexpected file creation
6. **Limit File Writing**: Configure `CssFileWriter.enabled = false` if not needed

## Known Limitations

- CSS content is not sanitized for malicious CSS (e.g., data exfiltration via `@import`)
- File writing has no rate limiting (controlled by application code)
- Large CSS files (>1MB) will raise errors (by design)

## Security Updates

Security updates will be released as patch versions (e.g., 1.0.1, 1.0.2) and will be announced via:
- GitHub Security Advisories
- RubyGems release notes
- CHANGELOG.md
