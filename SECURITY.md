# Security Policy

## Supported versions

Security fixes target the latest `main` branch and the latest published App Store version. Older versions are not maintained separately; update to the latest available version.

## Private reporting

Do not report vulnerabilities, credentials, private conversations, or reproduction data in a public issue.

Use GitHub's private vulnerability reporting for this repository. Include the affected commit or version, impact, reproduction steps using synthetic data, and any suggested mitigation. The maintainer will acknowledge a complete report within seven days and coordinate disclosure after a fix is available.

If private vulnerability reporting is unavailable, open a public issue containing only the words “Private security contact requested” and no vulnerability details.

## Secrets

If a real credential is committed, revoke it immediately before attempting history cleanup. Rewriting Git history does not invalidate a credential that has already been exposed.
