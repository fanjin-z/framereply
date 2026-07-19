---
layout: default
title: FrameReply Privacy Policy
permalink: /privacy
---

# FrameReply Privacy Policy

Effective July 15, 2026

FrameReply is an open-source iOS and iPadOS app. The project maintainer is the data controller for the limited processing described here. FrameReply does not operate an application server and does not use advertising, analytics, or tracking SDKs.

## Data FrameReply handles

FrameReply may handle participant and chat names, screenshots, message text, personas, communication goals, drafts, generated replies, provider account identifiers, and basic request-status information. This content can include personal data about the user and other conversation participants.

API keys are stored in Apple's Keychain using device-only protection. Extracted chats, personas, context, and replies are stored in the app's protected local database and excluded from device backups. Source images are normalized for transmission and are not stored by FrameReply as source files. The extracted message content remains in the local database until the user deletes it.

## AI provider processing

After explicit provider-specific consent, FrameReply sends selected content directly from the device to the active provider solely to analyze a conversation or generate replies. FrameReply does not receive a copy through a developer-operated server.

- OpenAI requests use the Responses API with `store: false`. OpenAI may still retain request data for abuse monitoring or other purposes described in its [API data controls](https://developers.openai.com/api/docs/guides/your-data) and [privacy policy](https://openai.com/policies/privacy-policy/).
- Z.ai International processing and retention are described in its [privacy policy](https://docs.z.ai/legal-agreement/privacy-policy).
- Zhipu China processing and retention are described in its [privacy policy](https://docs.bigmodel.cn/cn/terms/privacy-policy).

Z.ai International and Zhipu China use separate API endpoints and billing accounts. FrameReply does not restrict either option by the user's location. Provider terms and practices can change; review the selected provider's policy before consenting.

Provider usage can be linked to the provider account represented by the user's API key. The provider may charge that account. FrameReply does not sell provider access and contains no provider credit-purchase flow.

## Consent and lawful use

The user must affirm that they consent to provider processing and have permission or another lawful basis to upload the selected conversation and participant information. Consent is stored locally by provider and policy version. It can be revoked in **Settings → Privacy & Data**. Revocation blocks new AI requests until consent is granted again.

## Retention and deletion

Local data remains until the user deletes an individual chat/provider or chooses **Delete All Local Data**. Full deletion removes chats, messages, personas, context, drafts, consent records, provider settings, and API keys from the device. Reinstall detection purges orphaned FrameReply provider keys left in the Keychain.

Provider-side retention is controlled by the selected provider. Use the provider's account and privacy controls for provider-side requests.

## Tracking and disclosure

FrameReply does not track users, create advertising profiles, sell personal data, or share data with data brokers. Data is disclosed only to the provider selected by the user for app functionality, or when legally required.

## Children

FrameReply is not designed specifically for children. Users must meet the age and guardian-consent rules of their selected provider, and must not upload a minor's personal information without all legally required authorization.

## Contact

For privacy or deletion questions, contact the maintainer using this repository's GitHub private vulnerability-reporting channel. Do not put personal data in a public issue. General support instructions are available on the [support page](support).

Material policy changes will update the effective date and require renewed in-app consent when provider data sharing changes.
