# Progress label token budget

The progress-label request uses a 256-token generation ceiling. The real LiteLLM request builder sent that ceiling and explicit disabled thinking to a mocked Anthropic endpoint. The mock returned a short Japanese status label. The transport check took 73.9 ms locally, and all four progress-stream tests passed in 9 ms.

The mock used zero live calls, zero provider tokens, and $0 of provider cost. Live latency, completion rate, and output tone were not measured for the new ceiling.
