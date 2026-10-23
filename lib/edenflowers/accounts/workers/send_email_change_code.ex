defmodule Edenflowers.Accounts.Workers.SendEmailChangeCode do
  @moduledoc """
  Oban job that emails the verification code for a requested account email change.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  def enqueue(%{"email" => _, "code" => _, "locale" => _} = args) do
    args |> __MODULE__.new() |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"email" => email, "code" => code, "locale" => locale}}) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      Email.email_change_code(email, code) |> Mailer.deliver()
    end)
  end
end
