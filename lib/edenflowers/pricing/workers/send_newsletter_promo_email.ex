defmodule Edenflowers.Pricing.Workers.SendNewsletterPromoEmail do
  @moduledoc """
  Sends a subscriber their promotion code after signup, if the code remains usable.
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

  import Edenflowers.Actors

  alias Edenflowers.Pricing

  alias Edenflowers.Accounts
  alias Edenflowers.Email
  alias Edenflowers.Mailer

  def enqueue(%{"email" => _email} = args) do
    args |> __MODULE__.new() |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"email" => email, "locale" => locale}}) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn -> send_email(email, locale) end)
  end

  defp send_email(email, locale) do
    case Accounts.get_user_by_email(email, authorize?: false, load: [newsletter_promo: [:usage]]) do
      # The code is kept only once its email has gone, so a failed send is
      # retried as a welcome rather than as "you're already subscribed".
      {:ok, %{newsletter_promo: nil} = user} ->
        {:ok, promo} = Pricing.create_newsletter_promotion(actor: system_actor())

        with {:ok, _result} <- email |> Email.newsletter(:new, promo, locale) |> Mailer.deliver() do
          {:ok, _} = Accounts.set_newsletter_promo(user, promo.id, actor: system_actor())
          :ok
        end

      {:ok, %{newsletter_promo: promo}} ->
        message =
          if still_usable?(promo),
            do: Email.newsletter(email, :again_with_code, promo, locale),
            else: Email.newsletter(email, :again, nil, locale)

        with {:ok, _result} <- Mailer.deliver(message), do: :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Mirrors the expiry in Promotion's :by_code read, so the email never offers
  # a code checkout would turn down.
  defp still_usable?(%{usage: 0, expiration_date: expiration_date}) do
    today = Edenflowers.ShopTime.today()
    Date.compare(today, expiration_date) != :gt
  end

  defp still_usable?(_used), do: false
end
