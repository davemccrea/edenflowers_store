defmodule Edenflowers.Store.Order.Changes.UpsertUserAndAssignToOrder do
  @moduledoc """
  Creates or updates a user and assigns them to the order.

  This change finds or creates a user based on the customer_email
  and customer_name provided in the order. If the user already exists,
  their name is updated. The user is then associated with the order
  via the user_id field.

  If the `newsletter_opt_in` argument is true, the user is opted in to the
  newsletter and the same welcome/promo email worker the footer signup uses
  is enqueued. Opting in is one-way here — unchecking the box on a later
  visit does not unsubscribe an already-subscribed user.

  Also stamps `newsletter_offer_hidden?` on the order from the resolved user's
  subscription state, so checkout can decide whether to show the opt-in box
  without reading the user record under the customer's actor (the User read
  policy is own-record-only, so that read returns nil for guests).

  If user creation fails, an error is added to the changeset.
  """
  use Ash.Resource.Change
  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Accounts.User
  alias Edenflowers.Workers.SendNewsletterPromoEmail

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      customer_email = Ash.Changeset.get_argument_or_attribute(changeset, :customer_email)
      customer_name = Ash.Changeset.get_argument_or_attribute(changeset, :customer_name)
      newsletter_opt_in = Ash.Changeset.get_argument(changeset, :newsletter_opt_in) || false

      with {:ok, user} <- User.upsert(customer_email, customer_name, actor: system_actor()),
           {:ok, user} <- maybe_opt_in_to_newsletter(user, newsletter_opt_in, changeset) do
        Ash.Changeset.force_change_attributes(changeset,
          user_id: user.id,
          newsletter_offer_hidden?: newsletter_offer_hidden?(user)
        )
      else
        {:error, error} ->
          Logger.info("Failed to upsert user for order: #{inspect(error)}")

          Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidChanges{
            message: "Unable to create or update user account"
          })
      end
    end)
  end

  # The calcs aren't guaranteed loaded on the struct returned by upsert/update,
  # so load them explicitly (as system, since the User read policy is
  # own-record-only). newsletter_promo_used? resolves to nil when no promo is
  # assigned (nil > 0 is nil), so coerce the result to a strict boolean for the
  # non-null order column.
  defp newsletter_offer_hidden?(user) do
    user = Ash.load!(user, [:newsletter_subscribed?, :newsletter_promo_used?], actor: system_actor())
    !!(user.newsletter_subscribed? || user.newsletter_promo_used?)
  end

  defp maybe_opt_in_to_newsletter(user, false, _changeset), do: {:ok, user}

  defp maybe_opt_in_to_newsletter(user, true, changeset) do
    case User.update_newsletter_preference(user, true, actor: system_actor()) do
      {:ok, user} ->
        enqueue_newsletter_email(user.email, changeset)
        {:ok, user}

      {:error, _} = error ->
        error
    end
  end

  defp enqueue_newsletter_email(email, changeset) do
    locale = Ash.Changeset.get_attribute(changeset, :locale) || Gettext.get_locale(EdenflowersWeb.Gettext)

    SendNewsletterPromoEmail.enqueue(%{"email" => to_string(email), "locale" => locale})
  end
end
