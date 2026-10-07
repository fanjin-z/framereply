---
layout: default
title: AI Provider Costs and Model Choice
permalink: /ai-provider-costs
---

# AI Provider Costs and Model Choice

_Prices verified October 7, 2026._

These prices apply when you use your own API key and the selected provider bills your account. Prices may change; check the provider before setting a budget. FrameReply AI is a separate subscription with an included allowance; the App Store shows its regional price and eligible trial. See the [Terms](terms.md).

## Supported model prices

Standard pay-as-you-go prices per one million tokens. OpenAI rows use standard short-context pricing. MiniMax M3 rows use the standard service tier for inputs up to 512,000 tokens:

| Model | Input | Cached input | Output |
| --- | ---: | ---: | ---: |
| GPT-6 Luna | $0.10 | $0.01 | $0.50 |
| GPT-5.6 Terra | $2.00 | $0.20 | $12.00 |
| GPT-6.1 Sol | $2.00 | $0.10 | $10.00 |
| OpenRouter — Qwen3.7 Plus | $0.32 | $0.064 | $1.28 |
| MiniMax M3 (Intl.) | $0.30 | $0.06 | $1.20 |
| MiniMax M3 (China) | ¥2.10 | ¥0.42 | ¥8.40 |

Sources: [OpenAI API pricing](https://developers.openai.com/api/docs/pricing), [OpenRouter Qwen3.7 Plus](https://openrouter.ai/qwen/qwen3.7-plus), [MiniMax International pricing](https://platform.minimax.io/docs/guides/pricing-paygo), and [MiniMax China pricing](https://platform.minimaxi.com/docs/guides/pricing-paygo).

## Illustrative workflow costs

Each example includes import followed by fresh reply generation, for two provider requests. The 2,000 output tokens represent illustrative total billed output, including any reasoning tokens, not FrameReply's configured output ceiling. Providers bill actual generated tokens rather than the requested maximum:

- **Screenshot → replies:** 10,000 total input tokens, including one high-detail phone screenshot, and 2,000 output tokens.
- **Pasted text → replies:** 9,000 total input tokens and 2,000 output tokens.

The estimates use uncached rates: `(input tokens × input rate + output tokens × output rate) ÷ 1,000,000`.

| Model | Screenshot → replies | Pasted text → replies |
| --- | ---: | ---: |
| GPT-6 Luna | $0.0020 | $0.0019 |
| GPT-5.6 Terra | $0.0440 | $0.0420 |
| GPT-6.1 Sol | $0.0400 | $0.0380 |
| OpenRouter — Qwen3.7 Plus | $0.0058 | $0.0054 |
| MiniMax M3 (Intl.) | $0.0054 | $0.0051 |
| MiniMax M3 (China) | ¥0.0378 | ¥0.0357 |

These are illustrative comparisons, not measured averages. Actual charges vary with image count and size, conversation context, output length, reasoning, and tokenization. They exclude cache discounts and separate cache-write charges, connection validation, manual retries, OpenRouter's credit-purchase fee, taxes, and currency conversion. Provider billing records are authoritative.

## Choosing a model

- **GPT-6 Luna (Basic):** lowest-cost OpenAI option for routine use.
- **GPT-5.6 Terra (Advanced):** the existing middle-tier option.
- **GPT-6.1 Sol (Best):** quality-first option for subtle or complex conversations. Input rates match Terra, cached input is 50% cheaper, and output is about 17% cheaper.
- **Qwen3.7 Plus:** low-cost option billed through OpenRouter.
- **MiniMax M3:** low-cost direct option; choose International or China for the appropriate account region and currency.
