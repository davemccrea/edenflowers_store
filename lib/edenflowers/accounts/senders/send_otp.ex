defmodule Edenflowers.Accounts.Senders.SendOtp do
  @moduledoc """
  Sends a one-time password code to the user.
  """

  use AshAuthentication.Sender

  alias Edenflowers.Accounts.Workers.SendOtpEmail

  @dev_routes Application.compile_env(:edenflowers, :dev_routes, false)

  @impl true
  def send(user_or_email, otp_code, _opts) do
    # Lets OtpSignInLive prefill an admin's code in dev. The sender runs in
    # the LiveView process that requested the code.
    if @dev_routes and match?(%{admin: true}, user_or_email) do
      Process.put(:dev_otp_code, otp_code)
    end

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
