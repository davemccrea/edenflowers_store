defmodule Edenflowers.Orders.Order.Validations.CancellableByCustomer do
  @moduledoc "Refuses a customer's cancel once `cancellable_by_customer?` no longer holds."
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    if Ash.load!(changeset.data, :cancellable_by_customer?, authorize?: false, reuse_values?: false).cancellable_by_customer? do
      :ok
    else
      {:error,
       field: :fulfillment_status, message: ~t"This order can no longer be cancelled online. Please contact us."}
    end
  end
end
