---
layout: default
title: FrameReply Support
permalink: /support
---

# FrameReply Support

## FrameReply AI subscriptions

Open **Settings → AI Providers → FrameReply AI**. Its **…** menu contains **Restore Purchases** and **Refresh Status**.

- **Purchased, but not connected:** confirm you are using the Apple Account that made the purchase, then choose Restore Purchases. An active verified purchase connects FrameReply AI after any required data-sharing consent. If connection fails, retry on a stable network.
- **Switch providers:** select a connected provider in AI Providers. You can keep using your own keys while subscribed. Switching does not cancel your subscription; personal-provider charges are separate.
- **Period limit reached:** the included allowance is used up. Wait for the next eligible subscription period, or use your own provider. Restoring, reinstalling, and repeated purchase attempts do not replenish the allowance. Reaching a trial limit does not start paid billing early.
- **Allowance unavailable:** choose Refresh Status and retry later. An unavailable usage reading does not necessarily mean your allowance is exhausted.
- **Trial or price differs:** eligibility, duration, regional price, and availability come from the App Store. The purchase sheet shows the terms before confirmation.
- **Cancel:** use **iPhone Settings → your name → Subscriptions → FrameReply**. Deleting the app or its data does not cancel billing. See [Apple’s cancellation guide](https://support.apple.com/en-us/118428).
- **Refund:** submit Apple-billed purchase requests through [Apple’s refund process](https://support.apple.com/en-us/118223). Contact your provider for charges made using your own API key.

## Other troubleshooting

- Confirm the iPhone runs iOS 26 or later.
- For a personal-key provider, confirm its key is active and has quota. If consent needs to be reset, delete and reconnect that provider in **Settings → AI Providers**.
- Retry on a stable network and with a smaller image selection.
- For Shortcut issues, follow the [Shortcut troubleshooting guide](shortcuts.md).
- For local or server-side data deletion, see the [Privacy Policy](privacy.md). Local deletion does not delete subscription records or provider-held data.

## Contact

For app, subscription-access, privacy, or deletion questions, use the maintainer’s [contact page](https://fanjin.org/contact) and mention FrameReply. Include the app version, device/iOS version, approximate time of the issue, and steps to reproduce it. For subscription problems, say whether Apple shows an active subscription and whether this is an App Store or TestFlight installation.

Do not send API keys, purchase verification payloads, payment details, real conversations, or unredacted screenshots. Use a [public GitHub issue](https://github.com/fanjin-z/framereply/issues/new/choose) only for reports with synthetic data. Security-sensitive reports should use GitHub private vulnerability reporting.
