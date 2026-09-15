---
name: req-llm
description: "Expert on ReqLLM for making LLM API requests."
metadata:
  managed-by: usage-rules
---

<!-- usage-rules-skill-start -->
## Additional References

### req_llm

- [req_llm](references/req_llm/req_llm.md)

## Searching Documentation

```sh
mix usage_rules.search_docs "search term" -p req_llm
```

## Available Mix Tasks

- `mix req_llm.doctor` - Diagnose ReqLLM installation and runtime configuration
- `mix req_llm.gen` - Generate text or objects from any AI model
- `mix req_llm.install` - Install and configure ReqLLM for use in an application.
- `mix req_llm.install.docs`
- `mix req_llm.migration_audit` - Audit source for mechanical ReqLLM V2 migration work
- `mix req_llm.model_compat` - Validate ReqLLM model coverage with fixture-based testing
- `mix req_llm.model_support` - Inspect or generate evidence-backed model support tiers
- `mix req_llm.provider_drift` - Run bounded live provider drift verification
- `mix test.livebooks` - Validate livebook Elixir code blocks
<!-- usage-rules-skill-end -->
