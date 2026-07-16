defmodule Edenflowers.Accounts.User.Senders.SendOtp do
  @moduledoc """
  Sends a one-time password code to the user.
  """

  use AshAuthentication.Sender

  alias Edenflowers.Accounts.Workers.SendOtpEmail

  @impl true
  def send(user_or_email, otp_code, _opts) do
    email =
      case user_or_email do
        %{email: email} -> email
        email when is_binary(email) -> email
        email -> to_string(email)
      end

    locale = Gettext.get_locale(EdenflowersWeb.Gettext)

    SendOtpEmail.enqueue(%{
      "email" => to_string(email),
      "otp_code" => otp_code,
      "locale" => locale
    })
  end
end
