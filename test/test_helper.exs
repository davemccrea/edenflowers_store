# Define the mock module for StripeAPI
Mox.defmock(Edenflowers.StripeAPI.Mock, for: Edenflowers.StripeAPI.Behaviour)
Mox.defmock(Edenflowers.HereAPI.Mock, for: Edenflowers.HereAPI.Behaviour)
Mox.defmock(Edenflowers.HereTourPlanning.Mock, for: Edenflowers.HereTourPlanning.Behaviour)
Mox.defmock(Edenflowers.Papra.Mock, for: Edenflowers.Papra.Behaviour)
Mox.defmock(Edenflowers.Claude.Mock, for: Edenflowers.Claude.Behaviour)

# Skip Typst-dependent smoke tests when the binary isn't on PATH (devs
# without it locally). CI installs Typst, so the tag stays included there.
typst_opts = if System.find_executable("typst"), do: [], else: [exclude: [:typst]]

ExUnit.start(typst_opts)
Ecto.Adapters.SQL.Sandbox.mode(Edenflowers.Repo, :manual)
Faker.start()
