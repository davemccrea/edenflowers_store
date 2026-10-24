defmodule Edenflowers.ContactMessage.SendEmails do
  @moduledoc """
  Oban job that sends a contact form message to the shop and a copy to the
  sender.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  @impl true
  def perform(%Oban.Job{args: %{"locale" => locale} = message}) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      message |> Email.contact_message() |> Mailer.deliver()
    end)
  end
end
