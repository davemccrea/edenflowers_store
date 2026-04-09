# Define the mock module for StripeAPI
Mox.defmock(Edenflowers.StripeAPI.Mock, for: Edenflowers.StripeAPI.Behaviour)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Edenflowers.Repo, :manual)
Faker.start()
