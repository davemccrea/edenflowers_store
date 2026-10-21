defmodule Edenflowers.Orders.Changes.UpsertUserAndAssignToOrder do
  @moduledoc """
  Upserts a user from the order's `customer_email`/`customer_name` and assigns
  them to the order via `user_id`.

  If the `newsletter_opt_in` argument is true, the user is opted in to the
  newsletter and the same welcome/promo email worker the footer signup uses
  is enqueued. Opting in is one-way here — unchecking the box on a later
  visit does not unsubscribe an already-subscribed user. It runs after the
  order commits, so a failed opt-in is logged but never fails the order.
  """
  use Ash.Resource.Change
  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Accounts
  alias Edenflowers.Accounts.User
  alias Edenflowers.Pricing.Workers.SendNewsletterPromoEmail

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      customer_email = Ash.Changeset.get_argument_or_attribute(changeset, :customer_email)
      customer_name = Ash.Changeset.get_argument_or_attribute(changeset, :customer_name)

      case Accounts.upsert_user(customer_email, customer_name, actor: system_actor()) do
        {:ok, user} ->
          Ash.Changeset.force_change_attribute(changeset, :user_id, user.id)

        {:error, error} ->
          Logger.error("Failed to upsert user for order #{changeset.data.id}: #{inspect(error)}")

          Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidChanges{
            message: "Unable to create or update user account"
          })
      end
    end)
    |> Ash.Changeset.after_transaction(fn
      changeset, {:ok, order} ->
        if Ash.Changeset.get_argument(changeset, :newsletter_opt_in), do: opt_in_to_newsletter(order)
        {:ok, order}

      _changeset, error ->
        error
    end)
  end

  defp opt_in_to_newsletter(order) do
    locale = order.locale || to_string(Edenflowers.Format.locale())

    with {:ok, user} <- Ash.get(User, order.user_id, actor: system_actor()),
         {:ok, user} <- Accounts.update_newsletter_preference(user, true, locale, actor: system_actor()) do
      SendNewsletterPromoEmail.enqueue(%{"email" => to_string(user.email), "locale" => locale})
    else
      {:error, error} -> Logger.error("Newsletter opt-in for order #{order.id} failed: #{inspect(error)}")
    end
  end
end
