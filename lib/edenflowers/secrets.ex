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

  def secret_for(
        [:authentication, :strategies, :google, :client_id],
        Edenflowers.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:edenflowers, :google_client_id)
  end

  def secret_for(
        [:authentication, :strategies, :google, :client_secret],
        Edenflowers.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:edenflowers, :google_client_secret)
  end

  def secret_for(
        [:authentication, :strategies, :google, :redirect_uri],
        Edenflowers.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:edenflowers, :google_redirect_uri)
  end
end
