defmodule Edenflowers.Orders.Validations.Deletable do
  @moduledoc "Refuses to delete an order unless it is `deletable?`, saying why."
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    order = Ash.load!(changeset.data, :deletable?, authorize?: false, reuse_values?: false)

    cond do
      order.deletable? -> :ok
      order.origin == :custom -> {:error, message: ~t"has a payment, so it can only be cancelled"}
      true -> {:error, message: ~t"isn't a custom order"}
    end
  end
end
