defmodule Edenflowers.Payments.Changes.PayWithGiftVoucherCode do
  @moduledoc """
  Pays a Custom Order Jennie is placing from the Gift voucher whose
  `gift_voucher_code` she entered, through `pay_with_gift_voucher` once it's
  placed, so the voucher is refused and spent exactly as on an existing order.
  If the code is refused, the whole order placement fails and the error is
  attached to the gift voucher code field.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, order ->
      code = Ash.Changeset.get_argument(changeset, :gift_voucher_code)

      # Remap the error to gift_voucher_code before the outer placement transaction rolls back.
      with {:error, error} <-
             Ash.update(order, %{code: code},
               action: :pay_with_gift_voucher,
               actor: context.actor,
               authorize?: false,
               rollback_on_error?: false
             ),
           do: {:error, on_code_field(error)}
    end)
  end

  defp on_code_field(error) do
    error
    |> Ash.Error.to_error_class()
    |> Map.fetch!(:errors)
    |> Enum.map(fn
      %{field: :code} = error -> %{error | field: :gift_voucher_code}
      error -> error
    end)
  end
end
