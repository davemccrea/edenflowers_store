defmodule Edenflowers.Payments.Actions.SettleInvoiceFromBank do
  @moduledoc """
  Records a booked customer transfer on the open invoice whose reference
  number it quotes, through `record_payment` as if Jennie had entered it.
  """
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Edenflowers.Payments
  alias Edenflowers.Payments.Payment
  alias Edenflowers.Payments.ReferenceNumber
  alias Edenflowers.ShopTime

  @impl true
  def run(input, _opts, context) do
    %{reference_number: reference, amount: amount, booked_on: booked_on, bank_transaction_id: transaction_id} =
      input.arguments

    opts = Ash.Context.to_opts(context)

    with false <- recorded?(transaction_id),
         reference when is_binary(reference) <- ReferenceNumber.normalize(reference),
         {:ok, [invoice]} <-
           Payments.invoices_awaiting_bank_payment(
             reference,
             booked_on,
             [load: [:amount_unpaid]] ++ opts
           ),
         false <- Decimal.gt?(amount, invoice.amount_unpaid),
         {:ok, _invoice} <-
           Payments.record_invoice_payment(
             invoice,
             amount,
             %{paid_at: midday_on(booked_on), bank_transaction_id: transaction_id},
             opts
           ) do
      {:ok, true}
    else
      {:error, error} -> {:error, error}
      _not_recorded -> {:ok, false}
    end
  end

  defp recorded?(transaction_id) do
    Payment
    |> Ash.Query.filter(bank_transaction_id == ^transaction_id)
    |> Ash.exists?(authorize?: false)
  end

  # The bank gives a day; the monthly report files a payment by its Helsinki day.
  defp midday_on(date), do: date |> DateTime.new!(~T[12:00:00], ShopTime.timezone()) |> DateTime.shift_zone!("Etc/UTC")
end
