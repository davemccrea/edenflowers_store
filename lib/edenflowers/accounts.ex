defmodule Edenflowers.Accounts do
  use Ash.Domain,
    otp_app: :edenflowers

  resources do
    resource Edenflowers.Accounts.Token
    resource Edenflowers.Accounts.User
  end
end
