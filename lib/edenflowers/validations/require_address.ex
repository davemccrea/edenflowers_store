defmodule Edenflowers.Validations.RequireAddress do
  use Ash.Resource.Validation

  def atomic(_, _, _) do
    {
      :atomic,
      [:delivery_address],
      expr(
        fulfillment_option.fulfillment_method == :delivery and
          (is_nil(^atomic_ref(:delivery_address)) or
             ^atomic_ref(:delivery_address) == "")
      ),
      expr(
        error(
          Ash.Error.Changes.InvalidAttribute,
          %{
            field: :delivery_address,
            value: ^atomic_ref(:delivery_address),
            message: "is required"
          }
        )
      )
    }
  end
end
