# Together Qwen3.8 Flash compared with Qwen3.5 9B

Qwen3.8 Flash received the same six excerpts, English progress prompt, Japanese output request, 96-token ceiling, Together streaming endpoint, and reasoning-off field as in the previous 9B experiment. Each excerpt ran twice, for 12 new calls. The 9B column reuses the previous run. The models were measured from the local test environment in separate runs.

| Metric | Qwen3.5 9B | Qwen3.8 Flash |
| --- | ---: | ---: |
| Median time to first visible text | 288 ms | 1,221 ms |
| Median time to last visible text fragment | 519 ms | 1,629 ms |
| Output available within 500 ms, before quality review | 5/12 | 0/12 |
| Shortest Flash completion | — | 1,067 ms |
| Input / output tokens | ~2,880 / ~349 | 2,880 / 203 |
| Provider cost | ~$0.00057685 | $0.00052741 |

Together accepted the reasoning-off setting for Flash. The recorder detected no reasoning delta or positive reasoning-token count in its 12 streams. This is the observable API behavior. The Flash cost uses reported token usage and public Together list prices. The earlier 9B stream omitted usage, so its cost remains a tokenizer-based estimate.

Flash produced 12 nonempty, single-line strings at most 60 characters long and avoided the visibly garbled mixed-language wording found in the earlier 9B run. Some Flash lines still gave away a calculation result, stated the variable classification as a conclusion, or said it was holding back solutions. The length check does not score those content errors. The complete generated sentences are in the ignored local inputs directory. No product code or prompt was changed.
