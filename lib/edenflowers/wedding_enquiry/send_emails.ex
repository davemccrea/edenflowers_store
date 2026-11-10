defmodule Edenflowers.WeddingEnquiry.SendEmails do
  @moduledoc """
  Oban jobs that email a wedding enquiry to the shop and acknowledge it to the
  couple. They are separate jobs so a retry of one never resends the other.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  @impl true
  def perform(%Oban.Job{args: %{"acknowledgement" => true, "email" => email, "locale" => locale}}) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      email |> Email.wedding_enquiry_received() |> Mailer.deliver()
    end)
  end

  def perform(%Oban.Job{args: %{"locale" => locale} = args}) do
    enquiry = Map.update!(args, "wedding_date", &Date.from_iso8601!/1)

    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      enquiry |> Email.wedding_enquiry() |> Mailer.deliver()
    end)
  end
end
