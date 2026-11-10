defmodule Edenflowers.ContactMessage.SendEmails do
  @moduledoc """
  Oban jobs that email a contact form message to the shop and acknowledge it to
  the sender. They are separate jobs so a retry of one never resends the other.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  @impl true
  def perform(%Oban.Job{args: %{"acknowledgement" => true, "email" => email, "locale" => locale}}) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      email |> Email.contact_message_received() |> Mailer.deliver()
    end)
  end

  def perform(%Oban.Job{args: %{"locale" => locale} = message}) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      message |> Email.contact_message() |> Mailer.deliver()
    end)
  end
end
