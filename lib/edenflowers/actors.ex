defmodule Edenflowers.Actors do
  @moduledoc """
  Actor definitions for authorization in Ash resources.
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

      iex> Orders.finalize_checkout(order, actor: Edenflowers.Actors.system_actor())
  """
  def system_actor do
    %{system: true}
  end
end
