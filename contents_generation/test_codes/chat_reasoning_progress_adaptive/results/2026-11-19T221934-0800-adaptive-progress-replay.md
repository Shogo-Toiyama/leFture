# Progress labels during adaptive thinking on ordinary chat turns

The answer loop used the router's explicit reasoning route to decide whether to subscribe to the answer model's thinking stream. The two most recent completed turns on the developer account both used ordinary routing and had saved thinking text. Time from answer start to the first text delta was 9,373 ms and 6,584 ms. Retrieval ended 8 ms and 14 ms before answer start, respectively. The timestamps of individual thinking deltas are missing.

A local dry-run and a read-only Supabase replay used the production answer loop, stream adapter, progress prompt, and label request options. The provider was stubbed. The saved thinking text was replayed in artificial 40-character chunks with 1 ms yields. The replay used the stored reply language and answer model. Only operational metrics are recorded here.

| Turn | Original stages before text | Updated stages before text | Mock label calls, original → updated | Mock TTFT, original → updated |
| --- | --- | --- | --- | --- |
| Latest | Writing | Writing → Reasoning → 2 labels | 0 → 2 | 32 → 30 ms |
| Previous | Writing | Writing → Reasoning → 2 labels | 0 → 2 | 27 → 28 ms |

The dry-run also verified that a turn with no thinking before text stays in Writing, an explicit reasoning turn starts in Reasoning, and an unfinished label request is canceled without holding the first text delta. Four existing Python progress tests and all 14 English and Japanese web rendering cases passed. The mocked Anthropic request also confirmed a 256-token budget and disabled thinking for the label call. Provider token consumption and provider cost were zero for the replay. Production label latency, token consumption, cost, tone, and display frequency were not measured.

The answer stream now subscribes to thinking on every turn. The first nonblank thinking delta switches an ordinary turn to Reasoning. The existing summarizer uses complete thinking lines and publishes labels completed before the first text delta.
