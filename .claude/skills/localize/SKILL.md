---
name: localize
description: "Expert on Localize for internationalisation."
metadata:
  managed-by: usage-rules
---

<!-- usage-rules-skill-start -->
## Additional References

### localize

- [localize](references/localize/localize.md)

## Searching Documentation

```sh
mix usage_rules.search_docs "search term" -p localize
```

## Available Mix Tasks

- `mix localize.download_inflection` - Downloads inflection data files from the Localize CDN
- `mix localize.download_locales` - Downloads locale ETF files from the Localize CDN
- `mix localize.unit.gen_conversions` - Generates a dependency-free unit conversion module for embedded targets
- `mix localize.verify_locales` - Verifies locale ETF files against the bundled hash manifest
<!-- usage-rules-skill-end -->
