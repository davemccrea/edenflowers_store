defmodule Edenflowers.Accounts.Changes.RequestEmailChange do
  @moduledoc """
  Holds the new address as pending and emails it a code. Only a hash of the
  code is kept, so the address can't be confirmed from the database alone.
  A new request replaces any earlier one.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias AshAuthentication.Strategy.Otp.DefaultGenerator
  alias Edenflowers.Accounts.Workers.SendEmailChangeCode

  @code_lifetime_minutes 10

  @impl true
  def change(changeset, _opts, _context) do
    email = Ash.Changeset.get_argument(changeset, :email)

    if email && String.downcase(email) == String.downcase(to_string(changeset.data.email)) do
      Ash.Changeset.add_error(changeset, field: :email, message: ~t"That's already your email.")
    else
      request(changeset, email)
    end
  end

  defp request(changeset, email) do
    code = DefaultGenerator.generate(characters: :digits_only)

    changeset
    |> Ash.Changeset.force_change_attributes(%{
      pending_email: email,
      pending_email_code_hash: hash_code(code),
      pending_email_expires_at: DateTime.add(DateTime.utc_now(), @code_lifetime_minutes, :minute)
    })
    |> Ash.Changeset.after_action(fn _changeset, user ->
      {:ok, _job} =
        SendEmailChangeCode.enqueue(%{
          "email" => email,
          "code" => code,
          "locale" => Gettext.get_locale(EdenflowersWeb.Gettext)
        })

      {:ok, user}
    end)
  end

  def hash_code(code) do
    secret = Application.fetch_env!(:edenflowers, :token_signing_secret)
    :crypto.mac(:hmac, :sha256, secret, String.trim(code)) |> Base.encode64()
  end
end
