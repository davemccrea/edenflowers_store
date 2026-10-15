defmodule Edenflowers.WeddingEnquiry.SendEmails do
  use Oban.Worker, queue: :default

  alias Edenflowers.Email
  alias Edenflowers.Mailer

  def perform(%Oban.Job{args: %{"locale" => locale} = args}) do
    enquiry = Map.update!(args, "wedding_date", &Date.from_iso8601!/1)

    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      enquiry |> Email.wedding_enquiry() |> Mailer.deliver()
    end)
  end
end
