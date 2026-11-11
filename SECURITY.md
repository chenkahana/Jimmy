# Security policy

## Supported versions

Security fixes go into the latest App Store release of Jimmy. Older versions are not patched;
update to the latest version.

| Version | Supported |
|---|---|
| Latest | Yes |
| Earlier TestFlight builds | No |

## Reporting a vulnerability

**Please don't open a public issue.** Report it privately through GitHub:

1. Go to the repository's [Security tab](https://github.com/chenkahana/Jimmy/security).
2. Choose **Report a vulnerability** and describe the issue.

Include the affected version, device and iOS version, steps to reproduce, and the impact you expect.
A proof of concept helps.

### What to expect

- Acknowledgement within 3 business days.
- An initial assessment within 10 business days.
- Updates as the fix progresses, and credit in the release notes if you want it.

Please give us a reasonable chance to release a fix before disclosing the issue publicly.

## Scope

In scope:

- Jimmy app for iPhone
- JimmyKit package, including feed fetching and playback
- Podcast data handling and storage

Out of scope:

- Vulnerabilities in WebKit, iOS or Apple frameworks (report those to [Apple](https://security.apple.com))
- Issues on podcast feed hosting services
- Attacks that need a jailbroken device or physical access to an unlocked device
