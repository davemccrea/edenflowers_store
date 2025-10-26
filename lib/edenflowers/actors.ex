defmodule Edenflowers.Actors do
  @moduledoc """
  Actor definitions for authorization in Ash resources.

  Actors are used to represent different types of users or systems interacting with resources.
  They determine what actions are authorized through policy checks.
  """

  @doc """
  Returns a system actor for use with Ash actions that require elevated privileges.

  System actors bypass most authorization policies and should only be used for:
  - Webhook handlers (e.g., Stripe payment confirmations)
  - Background jobs (e.g., sending emails)
  - Internal system operations

  ## Examples

      iex> Edenflowers.Actors.system_actor()
      %{system: true}

      iex> Order.payment_received(order, actor: Edenflowers.Actors.system_actor())
  """
  def system_actor do
    %{system: true}
  end

  @doc """
  Returns a guest actor for use with unauthenticated checkout flows.

  Guest actors can read and update orders in the checkout state, but cannot:
  - Access completed orders
  - Access orders belonging to other users

  ## Examples

      iex> Edenflowers.Actors.guest_actor()
      %{guest: true}

      iex> Order.get_for_checkout!(order_id, actor: Edenflowers.Actors.guest_actor())
  """
  def guest_actor do
    %{guest: true}
  end
end
