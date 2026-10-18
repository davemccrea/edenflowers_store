Mox.defmock(Edenflowers.External.StripeAPI.Mock, for: Edenflowers.External.StripeAPI.Behaviour)
Mox.defmock(Edenflowers.External.HereAPI.Mock, for: Edenflowers.External.HereAPI.Behaviour)
Mox.defmock(Edenflowers.External.PapraAPI.Mock, for: Edenflowers.External.PapraAPI.Behaviour)
Mox.defmock(Edenflowers.External.ClaudeAPI.Mock, for: Edenflowers.External.ClaudeAPI.Behaviour)

# Skip Typst-dependent smoke tests when the binary isn't on PATH (devs
# without it locally). CI installs Typst, so the tag stays included there.
typst_opts = if System.find_executable("typst"), do: [], else: [exclude: [:typst]]

ExUnit.start(typst_opts)
# Committed before the sandbox starts, so concurrent tests read one row
# rather than each inserting it and waiting on the others' transactions.
Edenflowers.Fulfillment.get_shop_calendar!(authorize?: false)
Ecto.Adapters.SQL.Sandbox.mode(Edenflowers.Repo, :manual)
