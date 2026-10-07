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
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      case Accounts.get_user_by_email(email, authorize?: false, load: [newsletter_promo: [:usage]]) do
        {:ok, %{newsletter_promo: nil} = user} ->
          {:ok, promo} = Pricing.create_newsletter_promotion(actor: system_actor())
          Email.newsletter_promo(email, promo.code) |> Mailer.deliver()
          {:ok, _} = Accounts.set_newsletter_promo(user, promo.id, actor: system_actor())
          :ok

        {:ok, %{newsletter_promo: promo}} ->
          if still_usable?(promo) do
            Email.newsletter_already_subscribed(email, promo.code) |> Mailer.deliver()
          else
            Email.newsletter_resubscribed(email) |> Mailer.deliver()
          end

          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  # Mirrors the expiry in Promotion's :by_code read, so the email never offers
  # a code checkout would turn down.
  defp still_usable?(%{usage: 0, expiration_date: expiration_date}) do
    today = "Europe/Helsinki" |> DateTime.now!() |> DateTime.to_date()
    Date.compare(today, expiration_date) != :gt
  end

  defp still_usable?(_used), do: false
end
