# LLMLingua-2 Prompt Compression Benchmark

This folder contains experimental scripts and benchmark tools for **LLMLingua-2**, evaluating its effectiveness for compressing long student-attached documents (past exams, transcripts, external links) while preserving semantic meaning, technical terms, and code syntax.

## Overview

- **Model Variants**:
  - `microsoft/llmlingua-2-xlm-roberta-large-meetingbank`: General & English-optimized model. High semantic retention.
  - `microsoft/llmlingua-2-bert-base-multilingual-cased-meetingbank`: Multilingual-optimized model (handles Japanese/CJK token boundaries).
- **Key Parameters**:
  - `rate`: Target compression ratio (e.g. `0.5` means keeping ~50% of tokens).
  - `force_tokens`: Essential characters/keywords strictly protected from deletion (e.g. `\n`, `{`, `}`, code keywords).

## How to Run

Execute via the project virtual environment:

```bash
.venv/bin/python contents_generation/test_codes/llmlingua2_experiment/run_compression_benchmark.py
```

Results are saved to `compression_benchmark_results.json`.
