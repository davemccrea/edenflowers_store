defmodule EdenflowersWeb.Admin.DrawerPreview do
  @moduledoc """
  The customer email a drawer would send, from its form as Jennie has filled it
  in so far: her message and, for a payment or refund, the amount and how she
  hands it back. What the order and course pages' drawers share.
  """

  alias Edenflowers.Email.Preview
  alias EdenflowersWeb.Admin.Drawers

  def build(kind, record, params) do
    params = if kind == :refunded, do: Drawers.refund_form_params(record, params), else: params

    inputs = %{
      message: params["message"] || params["note"],
      refund: params["refund"] || params["amount"] || owed_back(record),
      amount: if(kind == :payment, do: params["amount"] || balance(record)),
      payment_method: payment_method(params["how"])
    }

    # Recording a payment emails the same receipt as the menu, for the amount entered.
    kind = if kind == :payment, do: :receipt, else: kind

    Preview.build(kind, record, inputs, if(params["in_swedish"] == "true", do: "sv-FI"))
  end

  # The refund form fills itself in from what's owed back, so an empty amount
  # reads as that until Jennie changes it.
  defp owed_back(record), do: record.balance |> Decimal.negate() |> Decimal.max(0) |> Decimal.to_string(:normal)

  defp balance(record), do: Decimal.to_string(record.balance, :normal)

  defp payment_method(how) when how in [nil, ""], do: :stripe
  defp payment_method(how) when is_binary(how), do: String.to_existing_atom(how)
end
