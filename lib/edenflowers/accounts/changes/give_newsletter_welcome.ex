defmodule Edenflowers.Accounts.Changes.GiveNewsletterWelcome do
  @moduledoc """
  Gives a first-time subscriber their one-use welcome code straight away, so
  checkout can apply it to the cart, and queues the welcome email and the push
  to MailerLite.

  Returning subscribers keep the code they have and are queued the
  already-subscribed wording instead. Both jobs are inserted in the same
  transaction, so an opt-in never commits without them; the push also
  resubscribes anyone who unsubscribed in MailerLite since.
  """
  use Ash.Resource.Change
  import Edenflowers.Actors

  alias Edenflowers.Accounts
  alias Edenflowers.Accounts.Workers.PushNewsletterSubscriber
  alias Edenflowers.Pricing
  alias Edenflowers.Pricing.Workers.SendNewsletterPromoEmail

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, user ->
      with {:ok, user, welcome?} <- give_code(user),
           {:ok, _job} <-
             SendNewsletterPromoEmail.enqueue(%{
               "email" => to_string(user.email),
               "locale" => user.locale,
               "welcome" => welcome?
             }),
           {:ok, _job} <- PushNewsletterSubscriber.enqueue(user),
           do: {:ok, user}
    end)
  end

  defp give_code(%{newsletter_promo_id: nil} = user) do
    with {:ok, promo} <- Pricing.create_newsletter_promotion(actor: system_actor()),
         {:ok, user} <- Accounts.set_newsletter_promo(user, promo.id, actor: system_actor()),
         do: {:ok, user, true}
  end

  defp give_code(user), do: {:ok, user, false}
end
