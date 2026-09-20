defmodule Edenflowers.Accounts.Workers.SendOtpEmail do
  use Oban.Worker, queue: :default

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  def enqueue(%{"email" => _, "otp_code" => _, "locale" => _} = args) do
    args |> __MODULE__.new() |> Oban.insert()
  end

  def perform(%Oban.Job{args: %{"email" => email, "otp_code" => otp_code, "locale" => locale}}) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      Email.otp_sign_in(email, otp_code) |> Mailer.deliver()
    end)
  end
end
