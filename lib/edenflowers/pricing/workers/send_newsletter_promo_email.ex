defmodule Edenflowers.Pricing.Workers.SendNewsletterPromoEmail do
  @moduledoc """
  Emails a subscriber after signup. `welcome` marks a first-time subscriber,
  who gets the welcome email with the code created at signup. Anyone else
  gets the already-subscribed wording, with their code if it remains usable.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      fields: [:args, :worker],
      keys: [:email],
      period: 3600,
      states: [:suspended, :scheduled, :available, :executing, :retryable, :completed]
    ]

  alias Edenflowers.Accounts
  alias Edenflowers.Email
  alias Edenflowers.Mailer

  def enqueue(%{"email" => _email} = args) do
    args |> __MODULE__.new() |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"email" => email, "locale" => locale} = args}) do
    welcome? = Map.get(args, "welcome", false)
    EdenflowersWeb.Gettext.with_app_locale(locale, fn -> send_email(email, locale, welcome?) end)
  end

  defp send_email(email, locale, welcome?) do
    with {:ok, user} <- Accounts.get_user_by_email(email, authorize?: false, load: [newsletter_promo: [:usable?]]),
         {:ok, _result} <- email |> message(user.newsletter_promo, locale, welcome?) |> Mailer.deliver(),
         do: :ok
  end

  defp message(email, promo, locale, true), do: Email.newsletter_welcome(email, promo, locale)
  defp message(email, %{usable?: true} = promo, locale, false), do: Email.already_subscribed(email, promo, locale)
  defp message(email, _promo, locale, false), do: Email.already_subscribed(email, nil, locale)
end
