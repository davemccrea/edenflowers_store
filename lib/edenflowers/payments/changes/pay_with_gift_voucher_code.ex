defmodule Edenflowers.Payments.Changes.PayWithGiftVoucherCode do
  @moduledoc """
  Pays a Custom Order Jennie is placing from the Gift voucher whose
  `gift_voucher_code` she entered, through `pay_with_gift_voucher` once it's
  placed, so the voucher is refused and spent exactly as on an existing order.
  A refused code fails the whole placing, its error on the code field.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, order ->
      code = Ash.Changeset.get_argument(changeset, :gift_voucher_code)

      # The placing's own transaction rolls back on the returned error, after it's moved to the code field.
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
