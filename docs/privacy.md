---
layout: default
title: FrameReply Privacy Policy
permalink: /privacy
---

# FrameReply Privacy Policy

Effective August 2, 2026

FrameReply is an open-source iPhone app. The project maintainer is the data controller for the limited processing described here. FrameReply does not operate an application server and does not use advertising, analytics, or tracking SDKs.

## Data FrameReply handles

FrameReply may handle participant and chat names, screenshots, message text, personas, communication goals, drafts, generated replies, provider account identifiers, and basic request-status information. This content can include personal data about the user and other conversation participants.

API keys are stored in Apple's Keychain using device-only protection. Extracted chats, personas, context, and replies are stored in the app's protected local database and excluded from device backups. Source images are normalized for transmission and are not stored by FrameReply as source files. The extracted message content remains in the local database until the user deletes it.

## AI provider processing

After explicit provider-specific consent, FrameReply sends selected content directly from the device to the active provider solely to analyze a conversation or generate replies. FrameReply does not receive a copy through a developer-operated server.

- OpenAI requests use the Responses API with `store: false`. OpenAI may still retain request data for abuse monitoring or other purposes described in its [API data controls](https://developers.openai.com/api/docs/guides/your-data) and [privacy policy](https://openai.com/policies/privacy-policy/).
- OpenRouter requests use the fixed `qwen/qwen3.7-plus` model. They pass through OpenRouter and are forwarded to Alibaba Cloud International. FrameReply denies provider data collection in each request and disables fallback routing, but this endpoint may still retain request data under its policies. Review the [OpenRouter privacy policy](https://openrouter.ai/privacy), [provider logging information](https://openrouter.ai/docs/guides/privacy/provider-logging/), and [Alibaba Cloud privacy policy](https://www.alibabacloud.com/help/en/legal/latest/alibaba-cloud-international-website-privacy-policy).
- MiniMax International processing and retention are described in its [privacy policy](https://platform.minimax.io/protocol/privacy-policy).
- MiniMax (China) processing and retention are described in its [privacy policy](https://platform.minimaxi.com/zh/protocol/privacy-policy).
- Z.ai International processing and retention are described in its [privacy policy](https://docs.z.ai/legal-agreement/privacy-policy).
- Zhipu China processing and retention are described in its [privacy policy](https://docs.bigmodel.cn/cn/terms/privacy-policy).

OpenRouter and Alibaba Cloud International are separate processors in the OpenRouter data path. MiniMax International and MiniMax (China) use separate API endpoints and billing accounts. Z.ai International and Zhipu China also use separate API endpoints and billing accounts. FrameReply does not restrict these options by the user's location. Provider terms and practices can change; review the selected provider's policy before consenting.

Provider usage can be linked to the provider account represented by the user's API key. The provider may charge that account. FrameReply does not sell provider access and contains no provider credit-purchase flow.

## Consent and lawful use

The user must affirm that they consent to provider processing and have permission or another lawful basis to upload the selected conversation and participant information. Consent is stored locally by provider and policy version. To withdraw consent, choose **Delete** from the provider menu in **Settings → Model Providers**. This removes the locally stored API key and consent.

## Retention and deletion

Local data remains until the user deletes an individual chat/provider or chooses **Delete All Local Data**. Full deletion removes chats, messages, personas, context, drafts, consent records, provider settings, and API keys from the device. Reinstall detection purges orphaned FrameReply provider keys left in the Keychain.

Deleting a provider does not revoke the key or delete provider-held data. Use the provider's account and privacy controls for those actions.

## Tracking and disclosure

FrameReply does not track users, create advertising profiles, sell personal data, or share data with data brokers. Data is disclosed only to the provider selected by the user for app functionality, or when legally required.

## Children

FrameReply is not designed specifically for children. Users must meet the age and guardian-consent rules of their selected provider, and must not upload a minor's personal information without all legally required authorization.

## Contact

For privacy or deletion questions, use the maintainer's [contact page](https://fanjin.org/contact) and mention FrameReply. Do not put personal data in a public issue. Security-sensitive reports should use this repository's GitHub private vulnerability-reporting channel. General support instructions are available on the [support page](support.md).

Material policy changes will update the effective date and require renewed in-app consent when provider data sharing changes.
