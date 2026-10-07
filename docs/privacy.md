---
layout: default
title: FrameReply Privacy Policy
permalink: /privacy
---

# FrameReply Privacy Policy

Effective October 7, 2026

FrameReply is an open-source iPhone app with an optional FrameReply AI subscription. 京跃（广州）科技有限公司 (GigaBeyond) provides the app and service and is the data controller for the processing described here. FrameReply does not use advertising, analytics, or tracking SDKs.

## Data FrameReply handles

FrameReply may handle participant and chat names, screenshots, message text, personas, communication goals, saved Personal Info about the user, drafts, generated replies, provider account identifiers, and basic request-status information. This content can include personal data about the user and other conversation participants.

API keys are stored in Apple's Keychain using device-only protection. Extracted chats, personas, Personal Info, context, and replies are stored in the app's protected local database and excluded from device backups. Source images are normalized for transmission and are not stored by FrameReply as source files. The extracted message content remains in the local database until the user deletes it.

## AI provider processing

After explicit provider-specific consent, FrameReply sends selected content and relevant saved Personal Info directly from the device to the active provider solely to analyze a conversation or generate replies. FrameReply does not receive a copy through a developer-operated server.

- OpenAI receives content directly when you connect your own OpenAI account. Its [API data controls](https://developers.openai.com/api/docs/guides/your-data) and [privacy policy](https://openai.com/policies/privacy-policy/) explain retention, including abuse monitoring.
- With your own OpenRouter key, OpenRouter and the provider serving your selected model receive the content. See the [OpenRouter privacy policy](https://openrouter.ai/privacy) and [provider retention information](https://openrouter.ai/docs/guides/privacy/provider-logging/).
- FrameReply AI sends selected content through [OpenRouter](https://openrouter.ai/privacy) to [OpenAI](https://developers.openai.com/api/docs/guides/your-data). We disable optional training and content logging, but these services may retain data under their policies, including for abuse monitoring. We do not promise zero retention.
- MiniMax International processing and retention are described in its [privacy policy](https://platform.minimax.io/protocol/privacy-policy).
- MiniMax (China) processing and retention are described in its [privacy policy](https://platform.minimaxi.com/zh/protocol/privacy-policy).

Provider availability and privacy practices vary by region and may change. Processing may occur outside your country; review the relevant policies before consenting.

Bring-your-own-key usage can be linked to the provider account represented by the user's API key, which the provider may charge. FrameReply AI usage is linked to a managed credential and limited by the subscription allowance.

## Subscription service data

We use [Amazon Web Services](https://aws.amazon.com/privacy/) in the United States to store purchase and subscription records, app-verification data, device identifiers linked to subscriptions, and usage records. We use these to verify purchases, restore access, enforce limits, and prevent abuse. AI access keys are stored encrypted; key identifiers and usage-management requests are shared with OpenRouter. Our subscription servers do not receive your screenshots, conversations, prompts, or generated replies.

[Apple](https://www.apple.com/legal/privacy/) handles purchases and payments. We do not receive your payment-card details or Apple Account password. Our servers log request identifiers, status, timing, and errors, excluding request contents and access keys. Services receiving requests also receive network information.

## Consent and lawful use

The user must affirm that they consent to provider processing and have permission or another lawful basis to upload selected conversation and participant information. Consent is stored locally by provider and policy version. For a personal-key provider, choose **Delete** from its menu in **Settings → AI Providers** to remove its key and consent. To stop sending content through FrameReply AI, select another provider or stop using AI features. To erase its locally saved key and consent, use **Settings → Privacy & Data → Delete All Local Data**; this also erases local conversations and other app data.

## Retention and deletion

Local data remains until the user deletes an individual chat/provider or chooses **Delete All Local Data**. Personal Info remains account-wide if a source chat is deleted. Removing an item keeps a local record to prevent relearning; **Delete All Local Data** removes all Personal Info records along with chats, messages, personas, context, drafts, consent records, provider settings, and API keys for currently supported providers from the device. Reinstall detection purges orphaned keys for currently supported providers from the Keychain.

Deleting local data does not cancel an Apple subscription, erase server-side subscription records, or delete data held by AI providers. Deleting a personal-key provider does not revoke its key at the provider. Use Apple’s subscription controls and the relevant provider’s account/privacy controls separately.

Server logs and failed Apple subscription updates are retained for up to 14 days. Subscription, linked-device, usage, and access-key records are not automatically deleted when a subscription ends; they support restoration, usage accounting, and abuse prevention. Contact us to request access, correction, or deletion. Records needed for legal obligations, fraud prevention, or disputes may be retained; backups expire under their retention schedule.

## Tracking and disclosure

FrameReply does not track users, create advertising profiles, sell personal data, or share data with data brokers. Data is shared with Apple, AWS, OpenRouter, and the active model provider as described above to operate purchases, subscription access, and AI features, or when legally required. If you contact support, we also process the information you choose to send to resolve your request.

## Children

FrameReply is not designed specifically for children. Users must meet the age and guardian-consent rules of their selected provider, and must not upload a minor's personal information without all legally required authorization.

## Contact

For privacy or deletion questions, use the maintainer's [contact page](https://fanjin.org/contact) and mention FrameReply. Do not put personal data in a public issue. Security-sensitive reports should use this repository's GitHub private vulnerability-reporting channel. General support instructions are available on the [support page](support.md).

Material policy changes will update the effective date.
