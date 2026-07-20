# Manual release and open-source runbook

This runbook intentionally keeps signing, App Store credentials, provider keys, metadata upload, and distribution out of the public repository and GitHub Actions.

## Repository publication gate

1. Make an offline backup clone that will never be published.
2. Configure Git to use a GitHub noreply address.
3. Use `git filter-repo --mailmap <temporary-mailmap>` to replace the historical personal address in every branch and tag. Keep the temporary mailmap outside the repository.
4. Delete obsolete remote refs, force-push only after reviewing the rewritten graph, and require all collaborators to re-clone.
5. Run gitleaks against all revisions and manually inspect filenames for `.env`, private keys, provisioning profiles, archives, and real-chat fixtures.
6. Confirm no real credentials remain valid. Revoke any credential that was ever committed even if history was rewritten.
7. Enable GitHub public secret scanning, push protection, private vulnerability reporting, protected `main`, and required review for repository configuration changes.

The current audit did not find a standard secret signature, but this check must be repeated after the history rewrite.

## App Store owner actions

- Configure GitHub Pages to publish `docs/`, then verify the Privacy, Terms, Support, and Age Suitability URLs are public and stable.
- Replace any maintainer/contact details required by the App Store Connect seller record.
- Publish both team-owned Shortcuts, insert their verified iCloud URLs in `ShortcutInstallationCatalog`, and test installation from a device that has never installed them.
- Complete App Store privacy labels using the manifest as a conservative baseline: Name, User ID, Photos or Videos, Emails or Text Messages, Other User Content, and Product Interaction; App Functionality; linked to the provider account; no tracking.
- Complete the age-rating questionnaire accurately. Do not override to 18+ unless the calculated content rating, a future custom EULA, or a selected-provider requirement applicable to every user makes that necessary.
- Confirm that the App Store storefront selection, provider disclosures, and privacy labels match the intended distribution. Provider availability inside FrameReply is not inferred from the user's storefront or location.
- Confirm the app uses no non-exempt or non-Apple cryptography before relying on `ITSAppUsesNonExemptEncryption = NO`.
- Use synthetic identities and conversations in every screenshot and review fixture.

## Manual archive and review

### Per-language release checklist

English is the only current App Store localization. For every future language, verify these as separate deliverables:

- App binary strings, plural rules, Dynamic Type, VoiceOver, and the primary flows on device.
- App Intents, Shortcuts parameter copy, prompts, dialogs, and returned presentation-language metadata.
- App Store name, subtitle, description, keywords, release notes, screenshots, and previews in App Store Connect.
- Privacy policy, terms, support, and age-suitability pages remain the canonical reviewed English documents unless qualified legal translation review is complete. App Store metadata localizations use the same English URLs.
- When the first non-English interface ships, add localized in-app copy explaining that the linked legal and support documents are available in English.
- Translator review using screenshots and context comments, followed by Double-Length and Bounded-String pseudolanguage QA.

App Store metadata localization is managed independently from the binary String Catalog and must not be inferred from it.

1. Copy `Config/Local.xcconfig.example` to the ignored `Config/Local.xcconfig` and set the distribution Team ID.
2. Select the shared `FrameReply` scheme and a generic iOS device in Xcode.
3. Run tests and Analyze, then choose **Product → Archive**.
4. In Organizer, run **Validate App** and inspect the privacy report, entitlements, icon, display name, bundle ID, versions, and export-compliance result.
5. Distribute to internal TestFlight first. Test fresh installs on physical iPhone and iPad, all supported orientations, VoiceOver, large Dynamic Type, offline/IPv6 networking, consent/revocation, deletion, and both Shortcuts.
6. Live-smoke-test every exposed provider/model with capped nonproduction credentials. Test invalid key, exhausted quota, timeout, malformed response, and provider outage behavior.
7. Upload the validated archive through Organizer and complete submission manually in App Store Connect.

## App Review notes template

Explain that FrameReply is a free companion to user-owned provider accounts, contains no purchase or credit-funding links, and sends content directly to the selected provider only after explicit consent. Provide exact navigation steps for provider setup, screenshot/text import, reply generation, consent revocation, full deletion, and Shortcut installation.

Place one temporary, budget-capped provider key in App Review Notes only. Never place it in the app, repository, screenshots, or build settings. Revoke it as soon as review completes.

If Apple treats BYOK as an external feature unlock rather than a free companion under Guideline 3.1.3(f), stop the release and resolve the business model before resubmitting.
