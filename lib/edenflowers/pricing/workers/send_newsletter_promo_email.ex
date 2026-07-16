defmodule Edenflowers.Pricing.Workers.SendNewsletterPromoEmail do
  use Oban.Worker,
    queue: :default,
    unique: [
      fields: [:args],
      keys: [:email],
      period: 3600,
      states: [:suspended, :scheduled, :available, :executing, :retryable, :completed]
    ]

  import Edenflowers.Actors

  alias Edenflowers.Pricing

  alias Edenflowers.Accounts
  alias Edenflowers.Email
  alias Edenflowers.Mailer

  def enqueue(%{"email" => _email} = args) do
    args |> __MODULE__.new() |> Oban.insert()
  end

  def perform(%Oban.Job{args: %{"email" => email, "locale" => locale}}) do
    Gettext.with_locale(EdenflowersWeb.Gettext, locale, fn ->
      case Accounts.get_user_by_email(email, authorize?: false, load: [:newsletter_promo]) do
        {:ok, %{newsletter_promo: nil} = user} ->
          {:ok, promo} = Pricing.create_newsletter_promotion(actor: system_actor())
          Email.newsletter_promo(email, promo.code) |> Mailer.deliver()
          {:ok, _} = Accounts.set_newsletter_promo(user, promo.id, actor: system_actor())
          :ok

        {:ok, %{newsletter_promo: %{usage: 0, code: code}}} ->
          Email.newsletter_already_subscribed(email, code) |> Mailer.deliver()
          :ok

        {:ok, %{newsletter_promo: _used}} ->
          Email.newsletter_resubscribed(email) |> Mailer.deliver()
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end
end
