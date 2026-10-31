defmodule Edenflowers.Orders.Order.Changes.UpsertUserAndAssignToOrder do
  @moduledoc """
  Upserts a user from the order's `customer_email`/`customer_name` and assigns
  them to the order via `user_id`.

  If the `newsletter_opt_in` argument is true, the user is signed up through
  the same `:subscribe_to_newsletter` action the footer uses, and their
  welcome code is applied to the cart unless it already has a code. They are
  still emailed the code, so it isn't lost if they leave the cart. Opting in
  is one-way here: unchecking the box on a later visit does not unsubscribe
  an already-subscribed user. A failed opt-in is logged but never fails the
  order.
  """
  use Ash.Resource.Change
  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Accounts
  alias Edenflowers.Orders.Order.Changes.ApplyPromotion

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      customer_email = Ash.Changeset.get_argument_or_attribute(changeset, :customer_email)
      customer_name = Ash.Changeset.get_argument_or_attribute(changeset, :customer_name)

      case Accounts.upsert_user(customer_email, customer_name, actor: system_actor()) do
        {:ok, user} ->
          changeset
          |> Ash.Changeset.force_change_attribute(:user_id, user.id)
          |> maybe_opt_in_to_newsletter(customer_email)

        {:error, error} ->
          Logger.error("Failed to upsert user for order #{changeset.data.id}: #{inspect(error)}")

          Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidChanges{
            message: "Unable to create or update user account"
          })
      end
    end)
  end

  defp maybe_opt_in_to_newsletter(changeset, customer_email) do
    if Ash.Changeset.get_argument(changeset, :newsletter_opt_in),
      do: opt_in_to_newsletter(changeset, customer_email),
      else: changeset
  end

  defp opt_in_to_newsletter(changeset, customer_email) do
    order = changeset.data
    locale = order.locale || to_string(Edenflowers.Format.locale())

    case Accounts.subscribe_to_newsletter(customer_email, locale,
           actor: system_actor(),
           load: [newsletter_promo: [:usable?]]
         ) do
      {:ok, %{newsletter_promo: %{usable?: true} = promo}} when is_nil(order.promotion_id) ->
        ApplyPromotion.copy_terms(changeset, promo)

      {:ok, _user} ->
        changeset

      {:error, error} ->
        Logger.error("Newsletter opt-in for order #{order.id} failed: #{inspect(error)}")
        changeset
    end
  end
end
