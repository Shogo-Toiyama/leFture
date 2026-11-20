# Display all available progress text

The progress worker originally required a nonempty single line of at most 60 characters. It did not use the provider finish reason. The new behavior joins nonempty lines with spaces and publishes all returned text except the standalone NONE sentinel. The generation budget remains 96 tokens, and the prompt continues to request a short label.

- The Python progress-stream suite passed all four checks in 11 ms. The long and multiline regression check failed before the change and passed afterward.
- A mocked Anthropic HTTP response ending at the 96-token budget returned visible text longer than 60 characters. LiteLLM reported the length finish reason and the worker published the full text supplied by the mock.
- The Flutter conversation widget displayed the full long label, then cleared it when the answer started.
- The Web status fixtures passed all 14 checks, including full long labels in English and Japanese. The Web indicator allows labels to wrap.

This validation made no live provider calls and incurred no model tokens or cost. Live latency, output tone, and the behavior of a deployed revision were not measured.
