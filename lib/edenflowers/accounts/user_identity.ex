defmodule Edenflowers.Accounts.UserIdentity do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.UserIdentity]

  postgres do
    table "user_identities"
    repo Edenflowers.Repo
  end

  user_identity do
    user_resource Edenflowers.Accounts.User
  end
end
