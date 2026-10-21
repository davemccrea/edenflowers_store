defmodule Edenflowers.Orders.Changes.UpsertUserAndAssignToOrder do
  @moduledoc """
  Upserts a user from the order's `customer_email`/`customer_name` and assigns
  them to the order via `user_id`.

  If the `newsletter_opt_in` argument is true, the user is opted in to the
  newsletter and the same welcome/promo email worker the footer signup uses
  is enqueued. Opting in is one-way here — unchecking the box on a later
  visit does not unsubscribe an already-subscribed user.
  """
  use Ash.Resource.Change
  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Accounts
  alias Edenflowers.Pricing.Workers.SendNewsletterPromoEmail

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      customer_email = Ash.Changeset.get_argument_or_attribute(changeset, :customer_email)
      customer_name = Ash.Changeset.get_argument_or_attribute(changeset, :customer_name)
      newsletter_opt_in = Ash.Changeset.get_argument(changeset, :newsletter_opt_in) || false

      with {:ok, user} <- Accounts.upsert_user(customer_email, customer_name, actor: system_actor()),
           {:ok, user} <- maybe_opt_in_to_newsletter(user, newsletter_opt_in, changeset) do
        Ash.Changeset.force_change_attribute(changeset, :user_id, user.id)
      else
        {:error, error} ->
          Logger.warning("Failed to upsert user for order #{changeset.data.id}: #{inspect(error)}")

          Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidChanges{
            message: "Unable to create or update user account"
          })
      end
    end)
  end

  defp maybe_opt_in_to_newsletter(user, false, _changeset), do: {:ok, user}

  defp maybe_opt_in_to_newsletter(user, true, changeset) do
    locale = Ash.Changeset.get_attribute(changeset, :locale) || to_string(Edenflowers.Format.locale())

    case Accounts.update_newsletter_preference(user, true, locale, actor: system_actor()) do
      {:ok, user} ->
        SendNewsletterPromoEmail.enqueue(%{"email" => to_string(user.email), "locale" => locale})
        {:ok, user}

      {:error, _} = error ->
        error
    end
  end
end
