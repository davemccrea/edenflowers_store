defmodule Edenflowers.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Edenflowers.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:edenflowers, :token_signing_secret)
  end
end
