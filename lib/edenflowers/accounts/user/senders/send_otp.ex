defmodule Edenflowers.Accounts.User.Senders.SendOtp do
  @moduledoc """
  Sends a one-time password code to the user.
  """

  use AshAuthentication.Sender

  import Swoosh.Email
  alias Edenflowers.Mailer

  @from_address Application.compile_env!(:edenflowers, :mailer_from_address)

  @impl true
  def send(user_or_email, otp_code, _opts) do
    email =
      case user_or_email do
        %{email: email} -> email
        email when is_binary(email) -> email
        email -> to_string(email)
      end

    new()
    |> from(@from_address)
    |> to(to_string(email))
    |> subject("Your sign-in code")
    |> text_body(body(otp_code: otp_code))
    |> Mailer.deliver!()
  end

  defp body(params) do
    """
    Your sign-in code is:

        #{params[:otp_code]}

    This code expires in 10 minutes.
    """
  end
end
