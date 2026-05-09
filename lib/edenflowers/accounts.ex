defmodule Edenflowers.Accounts do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Edenflowers.Accounts.Token
    resource Edenflowers.Accounts.User
  end
end
