# SECURITY

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Security Guidelines

StyleCapsule provides minimal security protections to assist with automated CSS scoping. The gem does not validate, sanitize, or secure CSS content itself—this is the application's responsibility.

### What StyleCapsule Protects

- **Path Traversal**: Filenames are validated when writing CSS files to prevent directory traversal attacks
- **Input Size Limits**: CSS content is limited to 1MB per component to prevent resource exhaustion
- **Scope ID Validation**: Capsule IDs are validated to prevent injection into HTML attributes

### What StyleCapsule Does NOT Control

**Developer Responsibility:**
- **CSS Content**: StyleCapsule does not validate or sanitize CSS content. Malicious CSS (e.g., data exfiltration via `@import`, CSS injection attacks) is not prevented by the gem
- **User Input**: Applications must validate and sanitize user-provided CSS before passing it to StyleCapsule
- **Developer Intent**: The gem trusts that developers provide safe CSS content from trusted sources

**Rails Framework:**
- HTML escaping is handled by Rails' built-in helpers (`content_tag`, etc.)
- Content Security Policy (CSP) must be configured at the application level
- File system permissions and access control are managed by the application

### Security Best Practices

1. **Validate User Input**: Never pass untrusted CSS content to StyleCapsule without validation
2. **Use Content Security Policy**: Configure CSP headers to restrict inline styles and external resources
3. **Sanitize User-Generated CSS**: If allowing user input, sanitize CSS before processing
4. **Keep Dependencies Updated**: Use supported Ruby (>= 3.0) and Rails versions with security patches
5. **Review Generated Files**: Periodically review files in `app/assets/builds/capsules/` if using file-based caching

### Reporting a Vulnerability

If you discover a security vulnerability, please **do not** open a public issue. Instead:

1. **Email**: contact@kiskolabs.com
2. **Subject**: `[SECURITY] style_capsule vulnerability report`
3. **Include**: Description, steps to reproduce, potential impact, and suggested fix (if any)

We will acknowledge receipt within 48 hours and provide an initial assessment within 7 days.

### Security Updates

Security updates are released as patch versions (e.g., 1.0.1, 1.0.2) and announced via:
- GitHub Security Advisories
- RubyGems release notes
- CHANGELOG.md
