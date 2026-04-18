defmodule Edenflowers.Workers.SendNewsletterPromoEmail do
  use Oban.Worker,
    queue: :default,
    unique: [fields: [:args], keys: [:email], period: 300, states: [:available, :scheduled, :executing]]

  import Edenflowers.Actors

  alias Edenflowers.Accounts.User
  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Store.Promotion

  def enqueue(%{"email" => _email} = args) do
    args
    |> __MODULE__.new()
    |> Oban.insert()
  end

  def perform(%Oban.Job{args: %{"email" => email, "locale" => locale}}) do
    Gettext.put_locale(EdenflowersWeb.Gettext, locale)

    case User.get_by_email(email, authorize?: false, load: [:newsletter_promo]) do
      {:ok, %{newsletter_promo: nil} = user} ->
        {:ok, promo} = Promotion.create_for_newsletter(actor: system_actor())
        Email.newsletter_promo(email, promo.code) |> Mailer.deliver()
        User.set_newsletter_promo(user, promo.id, actor: system_actor())

      {:ok, %{newsletter_promo: %{usage: 0, code: code}}} ->
        Email.newsletter_already_subscribed(email, code) |> Mailer.deliver()

      {:ok, %{newsletter_promo: _used}} ->
        Email.newsletter_resubscribed(email) |> Mailer.deliver()

      {:error, reason} ->
        {:error, reason}
    end
  end
end
