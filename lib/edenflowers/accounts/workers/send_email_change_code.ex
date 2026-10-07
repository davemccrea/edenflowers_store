defmodule Edenflowers.Accounts.Workers.SendEmailChangeCode do
  use Oban.Worker, queue: :default

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  def enqueue(%{"email" => _, "code" => _, "locale" => _} = args) do
    args |> __MODULE__.new() |> Oban.insert()
  end

  def perform(%Oban.Job{args: %{"email" => email, "code" => code, "locale" => locale}}) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      Email.email_change_code(email, code) |> Mailer.deliver()
    end)
  end
end
