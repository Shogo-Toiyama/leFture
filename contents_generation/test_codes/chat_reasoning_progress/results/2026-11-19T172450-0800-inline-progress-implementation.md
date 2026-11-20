# Inline reasoning progress implementation

The backend starts with one complete nonempty line, then uses groups of three new lines. A single request can be active per turn. If more than one group accumulates during that call, the newest pending group replaces the older one. Blank lines and unfinished fragments do not count. The answer's first text delta closes the progress worker, and error and stop exits also close it. Both clients display the resulting label in the existing stage indicator.

| Check | Result |
| --- | --- |
| Python 3.11 stream batching, invalid labels, pending groups, cancellation | 4 passed in 14 ms |
| Production UnifiedLLM on a mocked Anthropic HTTP response | Request shape, output parsing, and token usage verified |
| Web rendering with English and Japanese fixtures | 14 passed |
| Web production build | Passed |
| Flutter conversation, SSE, and widget tests | 106 passed |

These checks used zero live provider calls, zero live tokens, and $0 in provider cost. They exercised display style and state transitions with fixtures. Integrated live progress latency, answer TTFT, and generated label tone were not measured in this run.
