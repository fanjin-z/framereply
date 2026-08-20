---
layout: default
title: AI Provider Costs and Model Choice
permalink: /ai-provider-costs
---

# AI Provider Costs and Model Choice

_Prices verified August 20, 2026._

FrameReply uses your provided API key, and the selected provider bills your account. Prices may change, check the provider before setting a budget.

## Supported model prices

Standard pay-as-you-go prices per one million tokens. OpenAI rows use standard short-context pricing. MiniMax M3 rows use the standard service tier for inputs up to 512,000 tokens:

| Model | Input | Cached input | Output |
| --- | ---: | ---: | ---: |
| GPT-5.6 Luna | $0.20 | $0.02 | $1.20 |
| GPT-5.6 Terra | $2.00 | $0.20 | $12.00 |
| GPT-5.6 Sol | $5.00 | $0.50 | $30.00 |
| OpenRouter — Qwen3.7 Plus | $0.32 | $0.064 | $1.28 |
| MiniMax M3 (Intl.) | $0.30 | $0.06 | $1.20 |
| MiniMax M3 (China) | ¥2.10 | ¥0.42 | ¥8.40 |

Sources: [OpenAI API pricing](https://developers.openai.com/api/docs/pricing), [OpenRouter Qwen3.7 Plus](https://openrouter.ai/qwen/qwen3.7-plus), [MiniMax International pricing](https://platform.minimax.io/docs/guides/pricing-paygo), and [MiniMax China pricing](https://platform.minimaxi.com/docs/guides/pricing-paygo).

## Illustrative workflow costs

Each example includes import followed by fresh reply generation, for two provider requests. The 2,000 output tokens represent illustrative actual usage, not FrameReply's configured output ceiling. Providers bill actual generated tokens rather than the requested maximum:

- **Screenshot → replies:** 10,000 total input tokens, including one high-detail phone screenshot, and 2,000 output tokens.
- **Pasted text → replies:** 9,000 total input tokens and 2,000 output tokens.

The estimates use uncached rates: `(input tokens × input rate + output tokens × output rate) ÷ 1,000,000`.

| Model | Screenshot → replies | Pasted text → replies |
| --- | ---: | ---: |
| GPT-5.6 Luna | $0.0044 | $0.0042 |
| GPT-5.6 Terra | $0.0440 | $0.0420 |
| GPT-5.6 Sol | $0.1100 | $0.1050 |
| OpenRouter — Qwen3.7 Plus | $0.0058 | $0.0054 |
| MiniMax M3 (Intl.) | $0.0054 | $0.0051 |
| MiniMax M3 (China) | ¥0.0378 | ¥0.0357 |

These are illustrative comparisons, not measured averages. Actual charges vary with image count and size, conversation context, output length, and tokenization. They exclude cache discounts, connection validation, manual retries, OpenRouter's credit-purchase fee, taxes, and currency conversion. Provider billing records are authoritative.

## Choosing a model

- **GPT-5.6 Luna (Basic):** lowest-cost OpenAI option for routine use.
- **GPT-5.6 Terra (Advanced):** FrameReply's recommended balance of quality and cost.
- **GPT-5.6 Sol (Best):** quality-first option for subtle or complex conversations.
- **Qwen3.7 Plus:** low-cost option billed through OpenRouter.
- **MiniMax M3:** low-cost direct option; choose International or China for the appropriate account region and currency.
