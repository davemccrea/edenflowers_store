defmodule Edenflowers.Orders.Order.Calculations.PaymentInstruction do
  @moduledoc """
  How the customer should pay an unpaid order, following its payment link or
  agreed terms. Once handed over, an order no longer asks for payment in person.
  Nil when nothing is due or no payment method was agreed.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:unpaid?, :payment_link_open?]

  @impl true
  def calculate(records, _opts, _context), do: Enum.map(records, &instruction/1)

  defp instruction(%{unpaid?: false}), do: nil
  defp instruction(%{payment_link_open?: true}), do: :pay_now
  defp instruction(%{payment_terms: :invoice}), do: :invoice

  defp instruction(%{
         payment_terms: :on_fulfillment,
         fulfillment_status: status,
         fulfillment_method: :delivery
       })
       when status in [:pending, :ready],
       do: :on_delivery

  defp instruction(%{payment_terms: :on_fulfillment, fulfillment_status: status})
       when status in [:pending, :ready],
       do: :at_collection

  defp instruction(_record), do: nil
end
