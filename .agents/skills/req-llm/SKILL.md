---
name: req-llm
description: "Expert on ReqLLM for making LLM API requests."
metadata:
  managed-by: usage-rules
---

<!-- usage-rules-skill-start -->
## Additional References

- [req_llm](references/req_llm.md)

## Searching Documentation

```sh
mix usage_rules.search_docs "search term" -p req_llm
```

## Available Mix Tasks

- `mix req_llm.gen` - Generate text or objects from any AI model
- `mix req_llm.install` - Install and configure ReqLLM for use in an application.
- `mix req_llm.install.docs`
- `mix req_llm.model_compat` - Validate ReqLLM model coverage with fixture-based testing
- `mix test.livebooks` - Validate livebook Elixir code blocks
<!-- usage-rules-skill-end -->
