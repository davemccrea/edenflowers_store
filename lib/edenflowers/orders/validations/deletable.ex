defmodule Edenflowers.Orders.Validations.Deletable do
  @moduledoc """
  Only a Custom Order that no money has moved for can be deleted. Any other
  order is cancelled instead, so the accounts stay whole.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Ash.Query

  alias Edenflowers.Payments.Payment

  @impl true
  def validate(%{data: %{origin: :custom} = order}, _opts, context) do
    Payment
    |> Ash.Query.filter(order_id == ^order.id)
    |> Ash.exists?(Ash.Context.to_opts(context, authorize?: false))
    |> case do
      false -> :ok
      true -> {:error, message: ~t"has a payment, so it can only be cancelled"}
    end
  end

  def validate(_changeset, _opts, _context), do: {:error, message: ~t"isn't a custom order"}
end
