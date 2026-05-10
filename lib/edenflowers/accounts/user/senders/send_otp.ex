defmodule Edenflowers.Accounts.User.Senders.SendOtp do
  @moduledoc """
  Sends a one-time password code to the user.
  """

  use AshAuthentication.Sender

  import Swoosh.Email
  alias Edenflowers.Mailer

  @impl true
  def send(user_or_email, otp_code, _opts) do
    email =
      case user_or_email do
        %{email: email} -> email
        email when is_binary(email) -> email
        email -> to_string(email)
      end

    new()
    # TODO: Replace with your email
    |> from({"noreply", "noreply@example.com"})
    |> to(to_string(email))
    |> subject("Your sign-in code")
    |> html_body(body(otp_code: otp_code))
    |> Mailer.deliver!()
  end

  defp body(params) do
    """
    <p>Your sign-in code is:</p>
    <p style="font-size: 24px; font-weight: bold; letter-spacing: 4px;">#{params[:otp_code]}</p>
    <p>This code expires in 10 minutes.</p>
    """
  end
end
